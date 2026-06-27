import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'safe_space_screen.dart';
import '../services/chat_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ChatScreen — watercolor-illustrated companion chat
//
// All chat state (messages, history, loading flag) now lives in the
// ChatService singleton.  This screen is a pure view: it observes the service
// and rebuilds on every change.
//
// Benefit: chat persists when the user navigates to Home, Spaces, etc.
// When a response arrives on a different screen, ChatReadyBanner notifies the
// user.  Opening ChatScreen calls markAsRead() to clear the badge.
// ─────────────────────────────────────────────────────────────────────────────

// Palette
const Color _kTextDark      = Color(0xFF3D2817);
const Color _kTextSecondary = Color(0xFF6B4F36);
const Color _kCream         = Color(0xFFF5EAD3);
const Color _kCreamSoft     = Color(0xFFF9F0E1);
const Color _kUserBubble    = Color(0xFFE8D5B7);
const Color _kAIBubble      = Color(0xFFDDE8D5);
const Color _kLeafCircle    = Color(0xFFB5C9A8);
const Color _kLeafIcon      = Color(0xFF4A7C59);
const Color _kUserAvatar    = Color(0xFF6B8C6B);
const Color _kCoral         = Color(0xFFE8A89A);
const Color _kCheckTick     = Color(0xFF8B7355);

class ChatScreen extends StatefulWidget {
  final String? initialMessage;
  final bool isChaiMode;
  const ChatScreen({super.key, this.initialMessage, this.isChaiMode = false});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _chatService = ChatService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController      _scrollController = ScrollController();
  final FocusNode             _focusNode = FocusNode();

  /// Guard so we only navigate to PanicRoom once per session.
  bool _navigatedToPanic = false;

  @override
  void initState() {
    super.initState();
    _chatService.addListener(_onChatUpdate);
    // Opening the screen clears the unread badge — banner disappears.
    _chatService.markAsRead();

    // Scroll to bottom of any pre-existing messages (service persists across
    // navigations, so the list might already be populated).
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    // Check-in mode: plant a greeting bubble immediately.
    if (_chatService.isCheckInMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final hour = DateTime.now().hour;
        final greeting = hour < 12
            ? 'Good morning — how are you starting the day today? 🌿'
            : hour < 17
                ? 'Hey, checking in — how has today been treating you so far?'
                : 'Evening check-in — how are you doing as the day winds down?';
        _chatService.addGreetingMessage(greeting);
        _chatService.clearCheckInMode();
      });
    }

    // Chai mode: greeting from Chai when opened from Therapy screen.
    if (widget.isChaiMode || _chatService.isChaiMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_chatService.messages.isEmpty) {
          _chatService.addGreetingMessage(
            'Hi, I\'m Chai. 🌿 I\'m here to support you — no judgement, no rush. '
            'What\'s on your mind today?',
          );
        }
        _chatService.clearChaiMode();
      });
    }

    // If opened with a seed message (e.g. from a deep-link), send it.
    final seed = widget.initialMessage?.trim();
    if (seed != null && seed.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_chatService.sendMessage(seed));
      });
    }
  }

  @override
  void dispose() {
    _chatService.removeListener(_onChatUpdate);
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── Service listener ───────────────────────────────────────────────────────

  void _onChatUpdate() {
    if (!mounted) return;

    // User is ON the chat screen — mark any arriving response as read
    // immediately so the ChatReadyBanner never fires while we're here.
    if (_chatService.hasUnreadResponse) {
      _chatService.markAsRead();
    }

    setState(() {});

    // During streaming use a short scroll duration (100 ms) so the view
    // keeps up with the appearing text.  After streaming is done (or for
    // non-streaming responses) the normal 350 ms applies.
    _scrollToBottom(fast: _chatService.isWaitingForResponse);

    // Navigate to PanicRoom exactly once when the backend flags a crisis.
    if (_chatService.isCrisis && !_navigatedToPanic) {
      _navigatedToPanic = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(
          CupertinoPageRoute(
            fullscreenDialog: true,
            builder: (_) => const SafeSpaceScreen(),
          ),
        );
      });
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _scrollToBottom({bool fast = false}) {
    // Double post-frame: first frame re-lays out the new bubble,
    // second frame gives the updated maxScrollExtent.
    final dur = fast
        ? const Duration(milliseconds: 80)
        : const Duration(milliseconds: 350);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: dur,
          curve:    Curves.easeOut,
        );
      });
    });
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty || _chatService.isWaitingForResponse) return;
    _controller.clear();
    // Use streaming for word-by-word appearance.
    unawaited(_chatService.sendMessageStreaming(text));
  }

  Future<void> _dialHelpline(String number) async {
    final uri = Uri(
      scheme: 'tel',
      path: number.replaceAll(RegExp(r'[^0-9+]'), ''),
    );
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Couldn't open dialler — number is $number"),
              backgroundColor: const Color(0xFF4A9E85),
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Couldn't open dialler — number is $number"),
            backgroundColor: const Color(0xFF4A9E85),
          ),
        );
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final messages  = _chatService.messages;
    final isLoading = _chatService.isWaitingForResponse;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor:           Colors.transparent,
        statusBarIconBrightness:  Brightness.dark,
      ),
      child: Scaffold(
        // resizeToAvoidBottomInset: true shrinks the body when the keyboard
        // opens.  The floating input pill uses padding.bottom + 18 (never
        // viewInsets) so it stays pinned just above the keyboard without
        // double-counting the inset height.
        resizeToAvoidBottomInset: true,
        backgroundColor: _kCream,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // ── Layer 1: watercolor background ──
            Image.asset(
              'assets/illustrations/frame_1.png',
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
            ),
            // ── Layer 2: soft white scrim ──
            const ColoredBox(color: Color(0x22FFFFFF)),

            // ── Layer 3: scrollable content ──
            SafeArea(
              child: Column(
                children: [
                  _Header(
                    onBack: () => Navigator.of(context).pop(),
                    title: widget.isChaiMode ? 'Chai 🐱' : null,
                  ),
                  const SizedBox(height: 8),
                  _Subtitle(),
                  if (_chatService.isCrisis) ...[
                    const SizedBox(height: 12),
                    _CrisisBanner(onDial: _dialHelpline),
                  ],
                  const SizedBox(height: 12),
                  Expanded(
                    // Tap outside the keyboard to dismiss it
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => FocusScope.of(context).unfocus(),
                      child: messages.isEmpty
                          ? const _EmptyPrompt()
                          : ListView.builder(
                              controller: _scrollController,
                              // 110 pt leaves room for the floating glass pill.
                              // Body already shrinks for keyboard, so no extra
                              // viewInsets needed.
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
                              itemCount: messages.length,
                              itemBuilder: (_, i) {
                                final m = messages[i];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: ChatBubble(
                                    // Append a blinking block cursor to the
                                    // last AI bubble while streaming is active.
                                    text: (!m.isUser &&
                                            _chatService.isWaitingForResponse &&
                                            i == messages.length - 1 &&
                                            m.text.isNotEmpty)
                                        ? '${m.text}▊'
                                        : m.text,
                                    isUser:          m.isUser,
                                    timestamp:       m.timeString,
                                    isLoading:       m.isLoading,
                                    eduTopic:        m.eduTopic,
                                    // Only pass the subtitle to the loading bubble
                                    loadingSubtitle: m.isLoading
                                        ? _chatService.slowLoadMessage
                                        : null,
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Layer 4: floating glass input pill ──
            // IMPORTANT: use padding.bottom + 18 only — NOT viewInsets.bottom.
            // The Scaffold already shrinks the body height when the keyboard
            // opens; adding viewInsets would double-count and push the bar to
            // the top of the screen.
            Positioned(
              left:   16,
              right:  16,
              bottom: MediaQuery.of(context).padding.bottom + 18,
              child: _GlassInputBar(
                controller: _controller,
                focusNode:  _focusNode,
                onSend:     _sendMessage,
                isLoading:  isLoading,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header — back arrow, title, leaf logo
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final VoidCallback onBack;
  final String? title;
  const _Header({required this.onBack, this.title});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            _CircleIconButton(
              icon:     Icons.arrow_back_ios_new,
              onTap:    onBack,
              iconSize: 18,
            ),
            Expanded(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    title ?? 'Chat with your companion',
                    style: GoogleFonts.caveat(
                      fontSize:   24,
                      fontWeight: FontWeight.w700,
                      color:      _kTextDark,
                    ),
                  ),
                ),
              ),
            ),
            _CircleIconButton(
              icon:      Icons.eco_rounded,
              onTap:     () {},
              iconColor: _kLeafIcon,
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData  icon;
  final VoidCallback onTap;
  final double    iconSize;
  final Color     iconColor;
  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    this.iconSize  = 20,
    this.iconColor = _kTextDark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width:  40,
        height: 40,
        decoration: BoxDecoration(
          color: _kCreamSoft.withValues(alpha: 0.90),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: iconColor, size: iconSize),
      ),
    );
  }
}

class _Subtitle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Text(
        "A safe space to share. I'm here to listen.",
        textAlign: TextAlign.center,
        style: GoogleFonts.fraunces(
          fontSize:   13,
          fontStyle:  FontStyle.italic,
          color:      _kTextSecondary,
        ),
      ),
    );
  }
}

class _EmptyPrompt extends StatelessWidget {
  const _EmptyPrompt();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        "What's on your mind?",
        style: GoogleFonts.fraunces(fontSize: 16, color: _kTextSecondary),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Crisis banner — persistent helpline strip
// ─────────────────────────────────────────────────────────────────────────────

class _CrisisBanner extends StatelessWidget {
  final void Function(String number) onDial;
  const _CrisisBanner({required this.onDial});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin:  const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color:        _kCoral,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.support_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'If you need immediate help, reach out:',
                  style: GoogleFonts.fraunces(
                    fontSize:   13.5,
                    fontWeight: FontWeight.w600,
                    color:      Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _HelplineButton(
                  label:  'iCall',
                  number: '9152987821',
                  onTap:  () => onDial('9152987821'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HelplineButton(
                  label:  'Vandrevala',
                  number: '1860-2662-345',
                  onTap:  () => onDial('1860-2662-345'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HelplineButton extends StatelessWidget {
  final String label;
  final String number;
  final VoidCallback onTap;
  const _HelplineButton({
    required this.label,
    required this.number,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color:        Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.fraunces(
                fontSize:   12,
                fontWeight: FontWeight.w700,
                color:      const Color(0xFF9B4137),
              ),
            ),
            Row(
              children: [
                const Icon(
                  Icons.phone_in_talk_rounded,
                  size:  14,
                  color: Color(0xFF9B4137),
                ),
                const SizedBox(width: 4),
                Text(
                  number,
                  style: GoogleFonts.fraunces(
                    fontSize:   13,
                    fontWeight: FontWeight.w600,
                    color:      const Color(0xFF6B2C24),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chat bubble — user / AI / loading
// ─────────────────────────────────────────────────────────────────────────────

class ChatBubble extends StatelessWidget {
  final String  text;
  final bool    isUser;
  final String  timestamp;
  final bool    isLoading;
  final bool    showAvatar;
  final String? eduTopic;
  /// Shown as italic subtitle below the typing dots while the server responds.
  /// Driven by ChatService.slowLoadMessage ("Connecting…" / "Waking up…").
  final String? loadingSubtitle;

  const ChatBubble({
    super.key,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isLoading       = false,
    this.showAvatar      = true,
    this.eduTopic,
    this.loadingSubtitle,
  });

  static const Map<String, String> _eduDescriptions = {
    'comparison':    'Social comparison is a built-in survival mechanism — your brain constantly benchmarks against visible peers. Understanding this can help you catch the pattern before it spirals.',
    'overthinking':  'Stress and sleep deprivation weaken the brain\'s ability to interrupt anxious thought loops. Knowing this means you can address the root cause (rest) instead of blaming yourself.',
    'uncertainty':   'Your brain treats uncertainty as danger — it prefers bad news to no news. Recognising this can help you separate real threats from your nervous system\'s false alarms.',
    'burnout':       'Burnout is a depletion state, not a weakness. When output exceeds recovery for too long, the system runs dry. Understanding this points to the fix: rest, not willpower.',
    'rejection':     'After rejection, brains default to internal blame even when external factors are more likely. Seeing the pattern helps you challenge the "I\'m not good enough" narrative.',
    'sleep':         'Even one bad night amplifies anxiety by ~30%. When everything feels heavier than it should, sleep is often the hidden variable.',
    'pluralistic':   'Pluralistic ignorance means everyone privately struggles but publicly performs fine — so everyone assumes they\'re the only one struggling. You\'re not uniquely broken.',
    'imposter':      'Imposter syndrome is most intense when you\'re surrounded by talented people. The fact that you question yourself is evidence you care, not that you don\'t belong.',
    'other':         'Sometimes understanding why we feel something — not just that we feel it — takes away some of its weight.',
  };

  void _showEduSheet(BuildContext context) {
    final desc = _eduDescriptions[eduTopic] ?? _eduDescriptions['other']!;
    showModalBottomSheet(
      context: context,
      backgroundColor: _kCreamSoft,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.eco_outlined, size: 18,
                     color: _kLeafIcon.withValues(alpha: 0.7)),
                const SizedBox(width: 8),
                Text(
                  'Why Chai shared that',
                  style: GoogleFonts.caveat(
                    fontSize:   20,
                    fontWeight: FontWeight.w700,
                    color:      _kTextDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              desc,
              style: GoogleFonts.fraunces(
                fontSize: 14,
                height:   1.6,
                color:    _kTextDark,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Research shows that knowing why we feel something — '
              'not just that we feel it — reduces its intensity.',
              style: GoogleFonts.fraunces(
                fontSize:  13,
                fontStyle: FontStyle.italic,
                height:    1.5,
                color:     _kTextSecondary,
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 10),
                  decoration: BoxDecoration(
                    color:        _kLeafCircle.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Close',
                    style: GoogleFonts.fraunces(
                      fontSize:   14,
                      fontWeight: FontWeight.w600,
                      color:      _kLeafIcon,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * 0.75;
    final hasEdu = !isUser && eduTopic != null;

    final bubbleContent = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isUser ? _kUserBubble : _kAIBubble,
        borderRadius: BorderRadius.only(
          topLeft:     const Radius.circular(18),
          topRight:    const Radius.circular(18),
          bottomLeft:  Radius.circular(isUser ? 18 : 4),
          bottomRight: Radius.circular(isUser ? 4  : 18),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLoading)
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _TypingDots(),
                if (loadingSubtitle != null && loadingSubtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      loadingSubtitle!,
                      style: GoogleFonts.fraunces(
                        fontSize:  12,
                        fontStyle: FontStyle.italic,
                        color:     const Color(0xFF9AA8B8),
                      ),
                    ),
                  ),
              ],
            )
          else
            Text(
              text,
              style: GoogleFonts.fraunces(
                fontSize: 15,
                height:   1.5,
                color:    _kTextDark,
              ),
            ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                timestamp,
                style: GoogleFonts.fraunces(fontSize: 11, color: _kCheckTick),
              ),
              if (isUser) ...[
                const SizedBox(width: 4),
                const Icon(Icons.done_all, size: 13, color: _kCheckTick),
              ],
            ],
          ),
        ],
      ),
    );

    final bubble = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: hasEdu
          ? GestureDetector(
              onTap: () => _showEduSheet(context),
              child: Stack(
                children: [
                  bubbleContent,
                  Positioned(
                    bottom: 8,
                    right:  8,
                    child: Icon(
                      Icons.eco_outlined,
                      size:  12,
                      color: const Color(0xFF4A7C59).withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            )
          : bubbleContent,
    );

    final avatar = Container(
      width:  28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isUser ? _kUserAvatar : _kLeafCircle,
      ),
      alignment: Alignment.center,
      child: Icon(
        isUser ? Icons.person_rounded : Icons.eco_rounded,
        color: isUser ? Colors.white : _kLeafIcon,
        size:  16,
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment:
          isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: isUser
          ? [
              Flexible(child: bubble),
              const SizedBox(width: 8),
              if (showAvatar) avatar,
            ]
          : [
              if (showAvatar) avatar,
              const SizedBox(width: 8),
              Flexible(child: bubble),
            ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Typing dots — 3 dots with cycling opacity
// ─────────────────────────────────────────────────────────────────────────────

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        double op(int i) {
          final phase = (_ctrl.value - i / 3) % 1.0;
          final t = phase < 0.5 ? phase * 2 : 2 - phase * 2;
          return 0.25 + 0.75 * t.clamp(0.0, 1.0);
        }

        Widget dot(int i) => Opacity(
          opacity: op(i),
          child: Container(
            width:  7,
            height: 7,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: const BoxDecoration(
              color: _kLeafIcon,
              shape: BoxShape.circle,
            ),
          ),
        );

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [dot(0), dot(1), dot(2)],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Glass input pill — iOS "Liquid Glass" style
// ─────────────────────────────────────────────────────────────────────────────

class _GlassInputBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode             focusNode;
  final VoidCallback          onSend;
  final bool                  isLoading;

  const _GlassInputBar({
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.isLoading,
  });

  @override
  State<_GlassInputBar> createState() => _GlassInputBarState();
}

class _GlassInputBarState extends State<_GlassInputBar> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
    _hasText = widget.controller.text.trim().isNotEmpty;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    final has = widget.controller.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          decoration: BoxDecoration(
            color:        Colors.white.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.55),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color:      Colors.black.withValues(alpha: 0.06),
                blurRadius: 18,
                offset:     const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Leaf badge
              Container(
                width:  34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kLeafCircle.withValues(alpha: 0.55),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.7),
                    width: 1,
                  ),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.eco_rounded, color: _kLeafIcon, size: 18),
              ),
              const SizedBox(width: 10),

              // Input
              Expanded(
                child: TextField(
                  controller:  widget.controller,
                  focusNode:   widget.focusNode,
                  minLines:    1,
                  maxLines:    4,
                  style:       GoogleFonts.fraunces(fontSize: 16, color: _kTextDark),
                  cursorColor: _kTextDark,
                  decoration: InputDecoration(
                    hintText: 'Ask anything',
                    hintStyle: GoogleFonts.fraunces(
                      fontSize: 16,
                      color:    _kTextDark.withValues(alpha: 0.55),
                    ),
                    border:         InputBorder.none,
                    enabledBorder:  InputBorder.none,
                    focusedBorder:  InputBorder.none,
                    isDense:        true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onSubmitted: (_) => widget.onSend(),
                ),
              ),

              const SizedBox(width: 6),

              // Send button
              GestureDetector(
                onTap: widget.isLoading || !_hasText ? null : widget.onSend,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve:    Curves.easeOut,
                  width:    40,
                  height:   40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _hasText
                        ? _kTextDark
                        : Colors.white.withValues(alpha: 0.4),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.6),
                      width: 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.arrow_upward_rounded,
                    color: _hasText
                        ? Colors.white
                        : _kTextDark.withValues(alpha: 0.7),
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
