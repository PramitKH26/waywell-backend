import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/chat_service.dart';
import 'safe_space_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Chai's Lair — the single chat room for the whole app.
//
// Chai is the chatbot for everything. Therapy is no longer a separate screen:
// when the user mentions therapy / booking / professional help, Chai surfaces
// suggestion cards INSIDE the chat (detected client-side here so it works
// regardless of backend state; the backend prompt also emits [SUGGEST:*] tags
// once redeployed).
// ─────────────────────────────────────────────────────────────────────────────

const _kCream      = Color(0xFFF5EAD3);
const _kTextDark   = Color(0xFF3D2817);
const _kTextMuted  = Color(0xFF6B4F36);
const _kGreen      = Color(0xFF4A7C59);
const _kUserBubble = Color(0xFFE8D5B7);
const _kChaiBubble = Color(0xFFDDE8D5);
const _kCardBorder = Color(0xFFE8D5B7);

// Keywords that make Chai offer the therapy options card.
const _kTherapyTriggers = [
  'therapy', 'therapist', 'counsel', 'counsellor', 'counselor',
  'professional help', 'need help', 'see someone', 'seek help',
  'psychiatr', 'psycholog', 'book a session', 'booking',
];

class ChaisLairScreen extends StatefulWidget {
  /// When shown as a bottom-nav tab there's nothing to pop, so the back
  /// button is hidden.
  final bool asTab;
  const ChaisLairScreen({super.key, this.asTab = false});

  @override
  State<ChaisLairScreen> createState() => _ChaisLairScreenState();
}

class _ChaisLairScreenState extends State<ChaisLairScreen> {
  final _chat       = ChatService();
  final _controller = TextEditingController();
  final _scroll     = ScrollController();
  final _focus      = FocusNode();

  // Suggestion state machine (client-side).
  String?       _activeSuggestion;   // currently shown card
  String?       _pendingSuggestion;  // shown once Chai finishes replying
  final Set<String> _shownTopics = {};
  bool _navigatedToSafeSpace = false;

  @override
  void initState() {
    super.initState();
    _chat.addListener(_onUpdate);
    _chat.markAsRead();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chat.messages.isEmpty) {
        _chat.addGreetingMessage(_getChaiGreeting());
      }
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _chat.removeListener(_onUpdate);
    _controller.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _getChaiGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return "Good morning. I'm Chai — welcome to my lair. "
          "What's on your mind today? 🌿";
    } else if (hour < 17) {
      return "Hey, come in. I'm Chai. What's been on your mind today?";
    } else {
      return "Evening. Make yourself comfortable — what's going on?";
    }
  }

  void _onUpdate() {
    if (!mounted) return;
    if (_chat.hasUnreadResponse) _chat.markAsRead();

    // Reveal a queued suggestion card once Chai has finished replying.
    if (!_chat.isWaitingForResponse && _pendingSuggestion != null) {
      _activeSuggestion  = _pendingSuggestion;
      _pendingSuggestion = null;
    }

    setState(() {});
    _scrollToBottom(fast: _chat.isWaitingForResponse);

    // Crisis → Safe Space, once.
    if (_chat.isCrisis && !_navigatedToSafeSpace) {
      _navigatedToSafeSpace = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const SafeSpaceScreen(),
        ));
      });
    }
  }

  void _scrollToBottom({bool fast = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: Duration(milliseconds: fast ? 80 : 320),
          curve: Curves.easeOut,
        );
      });
    });
  }

  void _send([String? override]) {
    final text = (override ?? _controller.text).trim();
    if (text.isEmpty || _chat.isWaitingForResponse) return;
    if (override == null) _controller.clear();

    // Hide any stale card while a new turn is in flight.
    _activeSuggestion = null;

    // Detect a first therapy mention → queue the options card.
    final lower = text.toLowerCase();
    if (!_shownTopics.contains('therapy_question') &&
        _kTherapyTriggers.any(lower.contains)) {
      _shownTopics.add('therapy_question');
      _pendingSuggestion = 'therapy_question';
    }

    unawaited(_chat.sendMessageStreaming(text));
    _focus.unfocus();
  }

  void _chooseOption(String suggestion, String userPhrase) {
    setState(() => _activeSuggestion = null);
    _pendingSuggestion = suggestion;
    _send(userPhrase);
  }

  Future<void> _dial(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Call $number')),
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final messages = _chat.messages;
    // +1 trailing slot for the suggestion card when one is active.
    final showCard  = _activeSuggestion != null && !_chat.isWaitingForResponse;
    final itemCount = messages.length + (showCard ? 1 : 0);

    return Scaffold(
      backgroundColor: _kCream,
      body: Column(
        children: [
          _buildTopBanner(),
          _buildHelpBanner(),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => _focus.unfocus(),
              child: ListView.builder(
                controller: _scroll,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                itemCount: itemCount,
                itemBuilder: (_, i) {
                  if (showCard && i == messages.length) {
                    return _buildSuggestionCard(_activeSuggestion!);
                  }
                  final m = messages[i];
                  final streaming = !m.isUser &&
                      _chat.isWaitingForResponse &&
                      i == messages.length - 1 &&
                      m.text.isNotEmpty;
                  return _buildBubble(
                    m.isUser,
                    streaming ? '${m.text}▊' : m.text,
                    m.isLoading,
                  );
                },
              ),
            ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  // ── Top banner ──────────────────────────────────────────────────────────
  // The header IS the artwork (Chai'sRoom copy.png) — title + room baked in,
  // shown at its natural aspect so nothing is cropped or duplicated. Back +
  // menu buttons are overlaid.
  Widget _buildTopBanner() {
    // The artwork already has a back "‹" (top-left) and "⋯" (top-right) drawn
    // in. We overlay invisible tap zones on those corners instead of drawing
    // our own buttons, so nothing is duplicated.
    return SafeArea(
      bottom: false,
      child: Stack(
        children: [
          AspectRatio(
            aspectRatio: 1024 / 570,
            child: Image.asset(
              "assets/illustrations/Chai'sRoom copy.png",
              fit: BoxFit.cover,
              width: double.infinity,
              errorBuilder: (_, __, ___) => Container(
                color: _kChaiBubble,
                alignment: Alignment.center,
                child: const Text('🐱', style: TextStyle(fontSize: 56)),
              ),
            ),
          ),
          // Back (baked ‹) — disabled on the tab root where there's nothing
          // to pop.
          if (!widget.asTab)
            Positioned(
              top: 0, left: 0, width: 110, height: 96,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).maybePop(),
                child: const SizedBox.expand(),
              ),
            ),
          // Menu (baked ⋯)
          Positioned(
            top: 0, right: 0, width: 110, height: 96,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _showInfoSheet,
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }

  // Thin "Need immediate help" banner → Safe Space.
  Widget _buildHelpBanner() {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const SafeSpaceScreen(),
      )),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFE8A89A),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.spa_outlined, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Need immediate help? A safe space is here.',
                  style: GoogleFonts.fraunces(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF6B2D2D))),
            ),
            const Icon(Icons.arrow_forward, color: Color(0xFF6B2D2D), size: 15),
          ],
        ),
      ),
    );
  }

  // ── Bubbles ──────────────────────────────────────────────────────────────
  Widget _buildBubble(bool isUser, String text, bool loading) {
    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.72,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isUser ? _kUserBubble : _kChaiBubble,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isUser ? 16 : 4),
          bottomRight: Radius.circular(isUser ? 4 : 16),
        ),
      ),
      child: loading
          ? const _TypingDots()
          : Text(text,
              style: GoogleFonts.fraunces(
                  fontSize: 15, height: 1.45, color: _kTextDark)),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[_chaiAvatar(), const SizedBox(width: 8)],
          Flexible(child: bubble),
        ],
      ),
    );
  }

  Widget _chaiAvatar() {
    return Container(
      width: 36,
      height: 36,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: _kChaiBubble,
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/illustrations/logo.png',
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            const Center(child: Text('🐱', style: TextStyle(fontSize: 18))),
      ),
    );
  }

  // ── Input bar ──────────────────────────────────────────────────────────────
  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: const BoxDecoration(
          color: _kCream,
          border: Border(top: BorderSide(color: Color(0xFFE2D4BA))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                  color: _kGreen, shape: BoxShape.circle),
              child: const Icon(Icons.eco_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFE2D4BA)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  style: GoogleFonts.fraunces(fontSize: 15, color: _kTextDark),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    hintText: 'Type your message…',
                    hintStyle: GoogleFonts.fraunces(
                        fontSize: 15, color: const Color(0xFFB0957A)),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _send(),
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                    color: _kGreen, shape: BoxShape.circle),
                child: const Icon(Icons.arrow_upward_rounded,
                    color: Colors.white, size: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Suggestion cards (Task 3) ───────────────────────────────────────────────
  Widget _buildSuggestionCard(String type) {
    switch (type) {
      case 'mental_health_check':
        return _checkCard();
      case 'find_therapist':
        return _findTherapistCard();
      case 'read_stories':
        return _storiesCard();
      case 'therapy_question':
      default:
        return _therapyQuestionCard();
    }
  }

  Widget _cardShell({required Widget child}) => Container(
        margin: const EdgeInsets.fromLTRB(2, 4, 2, 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _kCardBorder),
        ),
        child: child,
      );

  Widget _therapyQuestionCard() {
    return _cardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "I'm glad you're thinking about reaching out for support.",
            style: GoogleFonts.fraunces(
                fontSize: 14, color: _kTextDark, height: 1.5),
          ),
          const SizedBox(height: 12),
          Text('What would be most helpful?',
              style: GoogleFonts.fraunces(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _kTextMuted)),
          const SizedBox(height: 10),
          _optionButton('🌱 Understand if therapy is right for me',
              () => _chooseOption('mental_health_check',
                  "I'd like to understand if therapy is right for me")),
          const SizedBox(height: 6),
          _optionButton('🔍 Find a therapist',
              () => _chooseOption('find_therapist',
                  "I think I'm looking for a therapist")),
          const SizedBox(height: 6),
          _optionButton('💬 Read similar stories',
              () => _chooseOption('read_stories',
                  "Can you share stories from people who felt the same?")),
        ],
      ),
    );
  }

  Widget _optionButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFE8EFE0),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kGreen.withValues(alpha: 0.3)),
        ),
        child: Text(label,
            style: GoogleFonts.fraunces(fontSize: 13, color: _kTextDark)),
      ),
    );
  }

  Widget _checkCard() {
    return _cardShell(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardImage('chai2.png'),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Mental Health Check',
                    style: GoogleFonts.fraunces(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _kTextDark)),
                const SizedBox(height: 2),
                Text('A quick, confidential check — 2–3 minutes.',
                    style: GoogleFonts.fraunces(
                        fontSize: 12.5, color: _kTextMuted, height: 1.4)),
                const SizedBox(height: 8),
                Row(children: [
                  _pill('Takes 2–3 min'),
                  const SizedBox(width: 6),
                  _pill('100% Private'),
                ]),
                const SizedBox(height: 12),
                _greenButton('Start Check-In →', () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const _WellbeingFormScreen(),
                  ));
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _findTherapistCard() {
    return _cardShell(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardImage('chai1.png'),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Find a Therapist',
                    style: GoogleFonts.fraunces(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _kTextDark)),
                const SizedBox(height: 2),
                Text(
                    "We're building our therapist directory. For now, iCall "
                    'connects you to trained counsellors — free.',
                    style: GoogleFonts.fraunces(
                        fontSize: 12.5, color: _kTextMuted, height: 1.45)),
                const SizedBox(height: 12),
                _greenButton('Call iCall', () => _dial('9152987821')),
                const SizedBox(height: 6),
                Text('Coming soon: Waywell therapist directory',
                    style: GoogleFonts.fraunces(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: const Color(0xFF9AA8B8))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _storiesCard() {
    return _cardShell(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardImage('chai5.png'),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Stories from people like you',
                    style: GoogleFonts.fraunces(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _kTextDark)),
                const SizedBox(height: 2),
                Text(
                    'Real people who felt the same way and came through it.',
                    style: GoogleFonts.fraunces(
                        fontSize: 12.5, color: _kTextMuted, height: 1.45)),
                const SizedBox(height: 12),
                _greenButton("Tell me more about what you're feeling", () {
                  _chooseOption('read_stories',
                      "I want to tell you more about how I'm feeling.");
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardImage(String name) => SizedBox(
        width: 64,
        height: 64,
        child: Image.asset(
          'assets/illustrations/$name',
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
              const Center(child: Text('🐱', style: TextStyle(fontSize: 36))),
        ),
      );

  Widget _pill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFF5EAD3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            style: GoogleFonts.fraunces(
                fontSize: 10, color: _kTextMuted, fontWeight: FontWeight.w500)),
      );

  Widget _greenButton(String label, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: _kGreen,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label,
              style: GoogleFonts.fraunces(
                  fontSize: 13,
                  color: Colors.white,
                  fontWeight: FontWeight.w500)),
        ),
      );

  void _showInfoSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: _kCream,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: const Color(0xFFE8D5B7),
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 18),
            Text('About Chai',
                style: GoogleFonts.caveat(fontSize: 24, color: _kTextDark)),
            const SizedBox(height: 8),
            Text(
              "Chai is your companion here — a soft place to think out loud. "
              "Chai isn't a doctor; for urgent help, reach a helpline below.",
              style: GoogleFonts.fraunces(
                  fontSize: 13.5, color: _kTextMuted, height: 1.5),
            ),
            const SizedBox(height: 16),
            _greenButton('Call iCall — 9152987821', () {
              Navigator.pop(context);
              _dial('9152987821');
            }),
            const SizedBox(height: 10),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Close',
                    style: GoogleFonts.fraunces(
                        color: const Color(0xFF9AA8B8))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Typing indicator
// ─────────────────────────────────────────────────────────────────────────────
class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
        ..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final t = (_c.value + i * 0.2) % 1.0;
            final o = 0.3 + 0.7 * (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Opacity(
                opacity: o,
                child: Container(
                  width: 7, height: 7,
                  decoration: const BoxDecoration(
                      color: _kTextMuted, shape: BoxShape.circle),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Compact wellbeing check — a soft, non-clinical 5-question self-reflection.
// Not a diagnosis; ends with a gentle, encouraging summary.
// ─────────────────────────────────────────────────────────────────────────────
class _WellbeingFormScreen extends StatefulWidget {
  const _WellbeingFormScreen();
  @override
  State<_WellbeingFormScreen> createState() => _WellbeingFormScreenState();
}

class _WellbeingFormScreenState extends State<_WellbeingFormScreen> {
  static const _questions = [
    'Over the last 2 weeks, how often have you felt down or hopeless?',
    'How often have you had little interest or pleasure in doing things?',
    'How often have you felt nervous, anxious, or on edge?',
    'How has your sleep been?',
    'How often have you felt able to cope with daily things?',
  ];
  // Option labels map to a 0–3 burden score (higher = more difficulty).
  static const _options = [
    'Not at all', 'Several days', 'More than half the days', 'Nearly every day',
  ];

  int _index = 0;
  final List<int> _answers = [];

  void _answer(int score) {
    _answers.add(score);
    if (_index < _questions.length - 1) {
      setState(() => _index++);
    } else {
      setState(() => _index = _questions.length); // done
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = _index >= _questions.length;
    return Scaffold(
      backgroundColor: _kCream,
      appBar: AppBar(
        backgroundColor: _kCream,
        elevation: 0,
        foregroundColor: _kTextDark,
        title: Text('Wellbeing Check',
            style: GoogleFonts.caveat(fontSize: 24, color: _kTextDark)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: done ? _buildResult() : _buildQuestion(),
        ),
      ),
    );
  }

  Widget _buildQuestion() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: (_index + 1) / _questions.length,
          backgroundColor: const Color(0xFFE8D5B7),
          color: _kGreen,
        ),
        const SizedBox(height: 24),
        Text('Question ${_index + 1} of ${_questions.length}',
            style: GoogleFonts.fraunces(fontSize: 12, color: _kTextMuted)),
        const SizedBox(height: 8),
        Text(_questions[_index],
            style: GoogleFonts.fraunces(
                fontSize: 19, color: _kTextDark, height: 1.4)),
        const SizedBox(height: 24),
        ...List.generate(_options.length, (i) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GestureDetector(
              onTap: () => _answer(i),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _kCardBorder),
                ),
                child: Text(_options[i],
                    style:
                        GoogleFonts.fraunces(fontSize: 15, color: _kTextDark)),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildResult() {
    final total = _answers.fold<int>(0, (a, b) => a + b);
    // Max 15. Soft, non-clinical bands.
    String title;
    String body;
    if (total <= 4) {
      title = 'You seem to be holding steady 🌿';
      body = "Things look manageable right now. Keep checking in with "
          "yourself — and I'm here whenever you want to talk.";
    } else if (total <= 9) {
      title = "You've been carrying a fair bit";
      body = "Some of this has been weighing on you. Talking it through can "
          "really help — therapy is one option worth considering, and there's "
          "no rush.";
    } else {
      title = "It sounds like things have been heavy";
      body = "What you're feeling is real, and you don't have to carry it "
          "alone. Speaking with a professional could make a real difference. "
          "If it ever feels like too much, please reach a helpline.";
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🌱', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text(title,
              textAlign: TextAlign.center,
              style: GoogleFonts.caveat(
                  fontSize: 30, color: _kTextDark, fontWeight: FontWeight.w500)),
          const SizedBox(height: 12),
          Text(body,
              textAlign: TextAlign.center,
              style: GoogleFonts.fraunces(
                  fontSize: 14.5, color: _kTextMuted, height: 1.6)),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              decoration: BoxDecoration(
                  color: _kGreen, borderRadius: BorderRadius.circular(24)),
              child: Text('Back to Chai',
                  style: GoogleFonts.fraunces(
                      fontSize: 15,
                      color: Colors.white,
                      fontWeight: FontWeight.w500)),
            ),
          ),
          const SizedBox(height: 10),
          Text('This is a reflection, not a diagnosis.',
              style: GoogleFonts.fraunces(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: const Color(0xFF9AA8B8))),
        ],
      ),
    );
  }
}
