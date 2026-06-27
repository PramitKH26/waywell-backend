import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'identity_service.dart';
import 'mood_service.dart';
import 'psychoed_service.dart';

// Stream endpoint URL (same base, different path)
const _kStreamUrl = '${ApiConfig.baseUrl}/chat/stream';

// ─────────────────────────────────────────────────────────────────────────────
// ChatMessage — shared data model used by ChatService and every UI widget.
// ─────────────────────────────────────────────────────────────────────────────

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool isLoading;
  final String? loadingText;          // reserved for future per-bubble subtitles
  final Map<String, dynamic>? story;
  final String? eduTopic;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isLoading  = false,
    this.loadingText,
    this.story,
    this.eduTopic,
  });

  /// Human-readable time string for display, e.g. "2:43 PM".
  String get timeString {
    final h = timestamp.hour > 12
        ? timestamp.hour - 12
        : (timestamp.hour == 0 ? 12 : timestamp.hour);
    final m = timestamp.minute.toString().padLeft(2, '0');
    final p = timestamp.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $p';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ChatService — in-memory singleton that owns all chat state.
//
// Lifecycle matches the iOS app process:
//   • Lock screen / home button → app suspended → state PRESERVED
//   • Swipe up in app-switcher (force-quit) → process killed → FRESH state
//
// Server warm-up is handled externally by WarmupService (called in main()).
// This service only deals with message state and network calls.
// ─────────────────────────────────────────────────────────────────────────────

class ChatService extends ChangeNotifier {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;
  ChatService._internal();

  // ── Internal state ─────────────────────────────────────────────────────────
  final List<ChatMessage> _messages = [];

  /// Conversation history sent to Gemini for multi-turn memory.
  /// Kept separate from _messages so loading bubbles never appear in the prompt.
  /// Capped at 40 entries (= 20 exchanges) to keep request size and latency low.
  final List<Map<String, String>> _apiHistory = [];

  bool   _isWaitingForResponse = false;
  bool   _hasUnreadResponse    = false;
  bool   _isCrisis             = false;
  String _slowLoadMessage      = '';

  Timer? _slowTimer1;
  Timer? _slowTimer2;
  Timer? _slowTimer3;

  // ── Public getters ─────────────────────────────────────────────────────────
  List<ChatMessage> get messages            => List.unmodifiable(_messages);
  bool              get isWaitingForResponse => _isWaitingForResponse;
  bool              get hasUnreadResponse    => _hasUnreadResponse;
  bool              get isCrisis             => _isCrisis;
  String            get slowLoadMessage      => _slowLoadMessage;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Call from ChatScreen.initState to clear the unread badge.
  void markAsRead() {
    if (_hasUnreadResponse) {
      _hasUnreadResponse = false;
      notifyListeners();
    }
  }

  /// Send [text] to the backend, update [messages], and notify all listeners.
  /// Safe to call without await — the service manages its own async state.
  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isWaitingForResponse) return;

    // ── Snapshot history BEFORE adding current message ────────────────────
    // This prevents the current user message appearing twice in the Gemini
    // contents array (once in history, once as the current turn).
    final cappedHistory = _apiHistory.length > 40
        ? _apiHistory.sublist(_apiHistory.length - 40)
        : List<Map<String, String>>.from(_apiHistory);

    // ── Optimistic UI update ──────────────────────────────────────────────
    _messages.add(ChatMessage(
      text: trimmed, isUser: true, timestamp: DateTime.now(),
    ));
    _messages.add(ChatMessage(
      text: '', isUser: false, timestamp: DateTime.now(), isLoading: true,
    ));
    _isWaitingForResponse = true;
    _slowLoadMessage      = '';
    notifyListeners();

    // ── Slow-load status messages ─────────────────────────────────────────
    // Staggered hints so the user isn't left in silence if the server is slow.
    // 5 s  → gentle note (normal for Railway warm-up on first use)
    // 12 s → prompt to check network (should not happen if cron is running)
    // 25 s → suggest mobile data (campus WiFi often blocks Railway)
    // All cleared the moment the response arrives.
    _slowTimer1 = Timer(const Duration(seconds: 5), () {
      _slowLoadMessage = 'Connecting to your companion…';
      notifyListeners();
    });
    _slowTimer2 = Timer(const Duration(seconds: 12), () {
      _slowLoadMessage = 'Still working — check your internet connection';
      notifyListeners();
    });
    _slowTimer3 = Timer(const Duration(seconds: 25), () {
      _slowLoadMessage =
          'Taking too long. College WiFi may be blocking the server — '
          'try switching to mobile data.';
      notifyListeners();
    });

    // ── Network call ──────────────────────────────────────────────────────
    // 40 s is generous: the backend replies in 5-8 s when reachable.
    // Keeping it below 90 s means the user gets feedback faster.
    try {
      final userId      = await IdentityService().getUserId();
      final moodContext = MoodService().getMoodContext();
      final response = await http
          .post(
            Uri.parse(ApiConfig.chatUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'text':         trimmed,
              'history':      cappedHistory,
              'user_id':      userId,
              'mood_context': moodContext,
            }),
          )
          .timeout(const Duration(seconds: 40));

      _cancelSlowTimers();
      _messages.removeWhere((m) => m.isLoading);

      if (response.statusCode == 200) {
        final data  = jsonDecode(response.body) as Map<String, dynamic>;
        final reply = (data['response'] ?? 'Thanks for sharing.').toString();
        final crisis = data['is_crisis'] == true;
        final eduTopic = data['edu_topic'] as String?;

        final displayed = crisis ? reply : _maybeWeavePsychoed(reply);

        _messages.add(ChatMessage(
          text:      displayed,
          isUser:    false,
          timestamp: DateTime.now(),
          story:     data['story'] as Map<String, dynamic>?,
          eduTopic:  eduTopic,
        ));

        _apiHistory.add({'role': 'user',      'content': trimmed});
        _apiHistory.add({'role': 'assistant', 'content': reply});

        if (crisis) _isCrisis = true;
        _hasUnreadResponse = true;
      } else {
        _messages.add(ChatMessage(
          text:      "I'm having a little trouble right now. Can you try once more?",
          isUser:    false,
          timestamp: DateTime.now(),
        ));
      }
    } catch (e) {
      _cancelSlowTimers();
      _messages.removeWhere((m) => m.isLoading);
      final errMsg  = e.toString();
      // Always log the actual error so it shows in flutter run console
      debugPrint('[ChatService] sendMessage error: $errMsg');
      final timeout = errMsg.contains('TimeoutException') ||
                      errMsg.contains('timed out') ||
                      errMsg.contains('SocketException') ||
                      errMsg.contains('Connection refused') ||
                      errMsg.contains('Connection reset') ||
                      errMsg.contains('Network is unreachable');
      _messages.add(ChatMessage(
        text: timeout
            ? "Can't reach your companion right now.\n\n"
                "The server is warm — this is a network issue on your device:\n"
                "• Switch to mobile data (college WiFi often blocks this)\n"
                "• Or connect to a different WiFi\n"
                "Then just type your message again."
            : "Something went wrong. Please try again.",
        isUser:    false,
        timestamp: DateTime.now(),
      ));
      if (timeout) _addPsychoedTip();
    }

    _isWaitingForResponse = false;
    notifyListeners();
  }

  /// Count of completed companion replies in this session. Used to pace
  /// inline psychoed nudges so they don't appear on every turn.
  int _companionReplyCount = 0;

  /// True when the user opened the app from the daily check-in notification.
  /// ChatScreen reads this on mount, plants a greeting bubble, and clears it.
  bool _isCheckInMode = false;
  bool get isCheckInMode => _isCheckInMode;

  void setCheckInContext() {
    _isCheckInMode = true;
    reset();
    _isCheckInMode = true; // reset() clears it; re-set after.
  }

  void clearCheckInMode() {
    _isCheckInMode = false;
  }

  bool _isChaiMode = false;
  bool get isChaiMode => _isChaiMode;

  void setChaiMode() {
    reset();
    _isChaiMode = true;
  }

  void clearChaiMode() {
    _isChaiMode = false;
  }

  /// Insert a greeting bubble (from the companion) without an API call.
  /// Used by ChatScreen when opened in check-in mode.
  void addGreetingMessage(String text) {
    _messages.add(ChatMessage(
      text:      text,
      isUser:    false,
      timestamp: DateTime.now(),
    ));
    _hasUnreadResponse = false;
    notifyListeners();
  }

  /// Weaves a soft psychoed nudge onto a companion reply, paced via
  /// PsychoedService. Returns the reply unchanged most turns.
  String _maybeWeavePsychoed(String reply) {
    final nudge = PsychoedService().maybeNudge(_companionReplyCount);
    _companionReplyCount++;
    if (nudge == null) return reply;
    return '$reply\n\n— $nudge';
  }

  /// Surface a calming/psychoed tip as a follow-up companion bubble whenever
  /// we can't reach the backend, so the user still gets something useful.
  void _addPsychoedTip() {
    final tip = PsychoedService().randomTip();
    _messages.add(ChatMessage(
      text:      'While we wait — here\'s something that might help:\n\n'
                 '${tip.title}\n\n${tip.body}',
      isUser:    false,
      timestamp: DateTime.now().add(const Duration(milliseconds: 1)),
    ));
  }

  // ── Streaming send ─────────────────────────────────────────────────────────

  /// Like [sendMessage] but uses the /chat/stream SSE endpoint.
  /// Words appear in the bubble as Gemini generates them — same total time,
  /// but the first characters show up within ~1 second instead of waiting for
  /// the full response.
  Future<void> sendMessageStreaming(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isWaitingForResponse) return;

    // Snapshot history BEFORE adding current message (prevents duplication).
    final cappedHistory = _apiHistory.length > 40
        ? _apiHistory.sublist(_apiHistory.length - 40)
        : List<Map<String, String>>.from(_apiHistory);

    // Optimistic UI — user bubble + loading AI bubble.
    final userTs = DateTime.now();
    _messages.add(ChatMessage(text: trimmed, isUser: true,  timestamp: userTs));
    final aiTs = DateTime.now();
    _messages.add(ChatMessage(text: '',      isUser: false, timestamp: aiTs,
                              isLoading: true));
    // Track the index of the AI bubble (it's always the last item right now).
    final aiIdx = _messages.length - 1;

    _isWaitingForResponse = true;
    _slowLoadMessage      = '';
    notifyListeners();

    // Slow-hint timers (in case streaming stalls unexpectedly).
    _slowTimer1 = Timer(const Duration(seconds: 5), () {
      _slowLoadMessage = 'Connecting to your companion…';
      notifyListeners();
    });
    _slowTimer2 = Timer(const Duration(seconds: 12), () {
      _slowLoadMessage = 'Still working — check your internet connection';
      notifyListeners();
    });
    _slowTimer3 = Timer(const Duration(seconds: 25), () {
      _slowLoadMessage =
          'Taking too long. College WiFi may be blocking the server — '
          'try switching to mobile data.';
      notifyListeners();
    });

    String accumulated = '';
    Map<String, dynamic>? storyData;

    try {
      final userId      = await IdentityService().getUserId();
      final moodContext = MoodService().getMoodContext();
      final req = http.Request('POST', Uri.parse(_kStreamUrl));
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode({
        'text':         trimmed,
        'history':      cappedHistory,
        'user_id':      userId,
        'mood_context': moodContext,
      });

      final streamed = await req.send().timeout(const Duration(seconds: 40));

      if (streamed.statusCode != 200) {
        throw Exception('HTTP ${streamed.statusCode}');
      }

      // Parse SSE lines as they arrive.
      await for (final raw in streamed.stream.transform(utf8.decoder)) {
        for (final line in raw.split('\n')) {
          if (!line.startsWith('data: ')) continue;
          final data = line.substring(6).trim();
          if (data == '[DONE]' || data.isEmpty) continue;

          Map<String, dynamic> event;
          try {
            event = jsonDecode(data) as Map<String, dynamic>;
          } catch (_) {
            continue; // skip malformed chunk
          }

          final type = event['type'] as String?;

          if (type == 'crisis') {
            _cancelSlowTimers();
            _messages[aiIdx] = ChatMessage(
              text:      (event['response'] ?? '').toString(),
              isUser:    false,
              timestamp: aiTs,
              isLoading: false,
            );
            _isCrisis          = true;
            _hasUnreadResponse = true;
            notifyListeners();
            break;

          } else if (type == 'story') {
            storyData = event['story'] as Map<String, dynamic>?;

          } else if (type == 'chunk') {
            _cancelSlowTimers(); // first chunk — clear hint timers
            accumulated += (event['text'] ?? '') as String;
            _messages[aiIdx] = ChatMessage(
              text:      accumulated,
              isUser:    false,
              timestamp: aiTs,
              isLoading: false,
              story:     storyData,
            );
            notifyListeners();

          } else if (type == 'done') {
            final doneText = (event['full_text'] ?? accumulated).toString();
            final eduTopic = event['edu_topic'] as String?;

            _apiHistory.add({'role': 'user',      'content': trimmed});
            _apiHistory.add({'role': 'assistant', 'content': doneText});

            final displayed = _isCrisis
                ? doneText
                : _maybeWeavePsychoed(doneText);
            if (aiIdx < _messages.length) {
              _messages[aiIdx] = ChatMessage(
                text:      displayed,
                isUser:    false,
                timestamp: aiTs,
                isLoading: false,
                story:     storyData,
                eduTopic:  eduTopic,
              );
            }
            _hasUnreadResponse = true;
            notifyListeners();

          } else if (type == 'error') {
            _cancelSlowTimers();
            _messages[aiIdx] = ChatMessage(
              text:      (event['response'] ?? "Something went wrong. Please try again.").toString(),
              isUser:    false,
              timestamp: aiTs,
              isLoading: false,
            );
            notifyListeners();
          }
        }
      }
    } catch (e) {
      _cancelSlowTimers();
      final errMsg = e.toString();
      debugPrint('[ChatService] streaming error: $errMsg');

      // Remove the loading bubble (or partial streaming bubble) and show error.
      if (aiIdx < _messages.length) {
        _messages.removeAt(aiIdx);
      }

      final isNetErr = errMsg.contains('TimeoutException') ||
          errMsg.contains('timed out')           ||
          errMsg.contains('SocketException')     ||
          errMsg.contains('Connection refused')  ||
          errMsg.contains('Connection reset')    ||
          errMsg.contains('Network is unreachable');

      _messages.add(ChatMessage(
        text: isNetErr
            ? "Can't reach your companion right now.\n\n"
                "The server is warm — this is a network issue on your device:\n"
                "• Switch to mobile data (college WiFi often blocks this)\n"
                "• Or connect to a different WiFi\n"
                "Then just type your message again."
            : "Something went wrong. Please try again.",
        isUser:    false,
        timestamp: DateTime.now(),
      ));
      if (isNetErr) _addPsychoedTip();
      notifyListeners();
    }

    _isWaitingForResponse = false;
    notifyListeners();
  }

  /// Wipe all state — fresh start.
  void reset() {
    _cancelSlowTimers();
    _messages.clear();
    _apiHistory.clear();
    _isWaitingForResponse = false;
    _hasUnreadResponse    = false;
    _isCrisis             = false;
    _slowLoadMessage      = '';
    _companionReplyCount  = 0;
    notifyListeners();
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  void _cancelSlowTimers() {
    _slowTimer1?.cancel();
    _slowTimer2?.cancel();
    _slowTimer3?.cancel();
    _slowLoadMessage = '';
  }
}
