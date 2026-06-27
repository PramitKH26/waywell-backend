import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';

const _kHistoryKey = 'mood_history_v2';
const _kLastCheck  = 'mood_last_check_ts';

// ─────────────────────────────────────────────────────────────────────────────
// MoodService — tracks user emotional state across sessions.
//
// Check-in is shown on first open of the day OR if >4 hours have passed.
// Mood history is persisted for 30 days in SharedPreferences.
// Mood context is passed to Gemini with every chat message.
// ─────────────────────────────────────────────────────────────────────────────

class MoodEntry {
  final String   mood;
  final DateTime timestamp;
  final String   source;

  const MoodEntry({
    required this.mood,
    required this.timestamp,
    this.source = 'app_open',
  });

  Map<String, dynamic> toJson() => {
    'mood':      mood,
    'timestamp': timestamp.toIso8601String(),
    'source':    source,
  };

  factory MoodEntry.fromJson(Map<String, dynamic> j) => MoodEntry(
    mood:      j['mood']   as String,
    timestamp: DateTime.parse(j['timestamp'] as String),
    source:    (j['source'] as String?) ?? 'app_open',
  );
}

class MoodService extends ChangeNotifier {
  static final MoodService _instance = MoodService._internal();
  factory MoodService() => _instance;
  MoodService._internal();

  String?          _currentMood;
  List<MoodEntry>  _history = [];
  bool             _loaded  = false;

  String?          get currentMood => _currentMood;
  List<MoodEntry>  get history     => List.unmodifiable(_history);

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_kHistoryKey);
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        _history   = list.map(MoodEntry.fromJson).toList();
        _prune();
        if (_history.isNotEmpty) _currentMood = _history.last.mood;
      } catch (_) {}
    }
    _loaded = true;
  }

  void _prune() {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    _history.removeWhere((e) => e.timestamp.isBefore(cutoff));
  }

  // ── Timing logic ──────────────────────────────────────────────────────────

  Future<bool> shouldShowCheckIn() async {
    await _ensureLoaded();
    final prefs   = await SharedPreferences.getInstance();
    final lastStr = prefs.getString(_kLastCheck);
    if (lastStr == null) return true;
    final last = DateTime.parse(lastStr);
    return DateTime.now().difference(last).inHours >= 4;
  }

  Future<void> markDismissed() async {
    // User dismissed without selecting — don't show again until next window.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastCheck, DateTime.now().toIso8601String());
  }

  // ── Core logging ──────────────────────────────────────────────────────────

  Future<void> logMood(String mood, String userId) async {
    await _ensureLoaded();
    final entry = MoodEntry(mood: mood, timestamp: DateTime.now());
    _history.add(entry);
    _currentMood = mood;
    _prune();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kHistoryKey,
      jsonEncode(_history.map((e) => e.toJson()).toList()),
    );
    await prefs.setString(_kLastCheck, DateTime.now().toIso8601String());
    notifyListeners();

    // Fire-and-forget to backend
    _postToBackend('/mood/log', {
      'user_id':   userId,
      'mood':      mood,
      'timestamp': entry.timestamp.toIso8601String(),
      'source':    'app_open',
    });
  }

  Future<void> logNextAction(String action, String userId) async {
    _postToBackend('/mood/action', {
      'user_id':      userId,
      'initial_mood': _currentMood ?? 'unknown',
      'next_action':  action,
    });
  }

  Future<void> logReflection(
      String beforeMood, String afterReflection, String userId) async {
    _postToBackend('/mood/reflection', {
      'user_id':         userId,
      'before_mood':     beforeMood,
      'after_reflection': afterReflection,
    });
  }

  // ── Gemini context ────────────────────────────────────────────────────────

  Map<String, dynamic> getMoodContext() {
    final recent = _history.reversed.take(5).map((e) => e.mood).toList();
    return {
      'current_mood':  _currentMood,
      'recent_moods':  recent,
    };
  }

  // ── Network ───────────────────────────────────────────────────────────────

  void _postToBackend(String path, Map<String, dynamic> body) {
    try {
      http.post(
        Uri.parse('${ApiConfig.baseUrl}$path'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).catchError((e) => http.Response('', 0));
    } catch (_) {}
  }
}
