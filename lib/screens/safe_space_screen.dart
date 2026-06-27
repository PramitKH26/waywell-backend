import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/memory_service.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// Safe Space
///
/// Opens when the user is in crisis. Calm, dim, warm. Slow exhale > inhale.
/// Sections (top → bottom):
///   1. Immediate reassurance
///   2. Breathing lantern (4s inhale / 6s exhale, gentle haptics on transitions)
///   3. 5-4-3-2-1 grounding (one sense at a time)
///   4. Comforting anchor (saved memory or universal message)
///   5. Helplines (iCall, KIRAN, Vandrevala)
///
/// Safety: in-app dimming overlay only — NO device brightness changes.
/// No ice / cold-water techniques, no forced breath holds, no red/white,
/// no heavy haptics.
/// ─────────────────────────────────────────────────────────────────────────

// ─── Palette ─────────────────────────────────────────────────────────────
const _kText        = Color(0xFFC4CDD9);
const _kTextMuted   = Color(0xFF9AA8B8);
const _kAccent      = Color(0xFF6B8CAE);
const _kHelpline    = Color(0xFF4A9E85);
const _kLanternCore = Color(0xFFFFE0A3);
const _kLanternHalo = Color(0xFFFFD98A);
const _kCardBg      = Color(0xFF1A2530);
const _kCardSofterBg = Color(0xFF2A3540);
const _kPipDim      = Color(0xFF35454F);
const _kBadgeBg     = Color(0xFF2D4A6B);

/// Breath cycle brightness: 4s inhale (0–0.4) → 6s exhale (0.4–1.0).
/// Returns 0 at full exhale, 1 at the top of the in-breath. Shared by the
/// breath label and the fireflies so they pulse together.
double breathBrightness(double t) {
  if (t < 0.4) {
    return Curves.easeInOut.transform((t / 0.4).clamp(0.0, 1.0));
  }
  return Curves.easeInOut.transform((1 - (t - 0.4) / 0.6).clamp(0.0, 1.0));
}

class SafeSpaceScreen extends StatefulWidget {
  const SafeSpaceScreen({super.key});

  @override
  State<SafeSpaceScreen> createState() => _SafeSpaceScreenState();
}

class _SafeSpaceScreenState extends State<SafeSpaceScreen>
    with SingleTickerProviderStateMixin {
  // One shared breath cycle drives both the breath label AND the fireflies,
  // so the fireflies glow on the in-breath and dim on the out-breath.
  late final AnimationController _breath;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  // ── Fixed-screen firefly positions ─────────────────────────────────────────
  // Generated once with a fixed seed so they always appear in the same places.
  // They are placed in Layer 3 of the root Stack — OUTSIDE the scroll view —
  // so scrolling never moves them.
  List<Widget> _buildFireflies() {
    final r = math.Random(42);
    return List.generate(12, (i) {
      return _FixedFirefly(
        key: ValueKey('ff_$i'),
        cx:   22 + r.nextDouble() * 346,   // x: 22 → 368 pt
        cy:  110 + r.nextDouble() * 500,   // y: 110 → 610 pt
        size: 3.5 + r.nextDouble() * 2.5,  // core dot: 3.5 → 6 pt
        seed: i + 7,
        breath: _breath,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Height available inside the SafeArea for the atmospheric "first fold".
    // We subtract a 72 pt peek so the top edge of the grounding card is
    // just visible, signalling the user there is more to scroll to.
    final screenH  = MediaQuery.of(context).size.height;
    final topInset = MediaQuery.of(context).padding.top;
    final atmosH   = (screenH - topInset - 72).clamp(300.0, 900.0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0F1A),
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Layer 1 — background illustration (bears + lantern + lake)
            Image.asset(
              'assets/illustrations/panic_room_bg.png',
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, _, _) =>
                  Container(color: const Color(0xFF0A0F1A)),
            ),
            // Layer 2 — dimming overlay (in-app only, no brightness change)
            Container(color: Colors.black.withValues(alpha: 0.45)),

            // Layer 3 — FIXED fireflies (never scroll with content).
            ..._buildFireflies(),

            // Layer 4 — scrollable content on top
            SafeArea(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Atmospheric first fold ──────────────────────────────
                    // Exactly one viewport tall (minus peek).  The fireflies
                    // glow through the empty space below the breath text.
                    // User sees only calm + atmosphere, then scrolls for help.
                    ConstrainedBox(
                      constraints: BoxConstraints(minHeight: atmosH),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const _CloseRow(),
                          const _Reassurance(),
                          const SizedBox(height: 60),
                          BreathingLantern(cycle: _breath),
                        ],
                      ),
                    ),

                    // ── Scroll-down content ─────────────────────────────────
                    // Grounding, anchor and helplines start just below the fold.
                    const _GroundingCard(),
                    const SizedBox(height: 24),
                    const _ComfortAnchor(),
                    const SizedBox(height: 24),
                    const _HelplineSection(),
                    const SizedBox(height: 24),
                    const _FinalNote(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Section 1 — Close button + reassurance text
// ─────────────────────────────────────────────────────────────────────────

class _CloseRow extends StatelessWidget {
  const _CloseRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Align(
        alignment: Alignment.centerRight,
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.25),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.close, color: _kText, size: 20),
          ),
        ),
      ),
    );
  }
}

class _Reassurance extends StatelessWidget {
  const _Reassurance();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 0),
      child: Column(
        children: [
          Text(
            "You're safe.",
            textAlign: TextAlign.center,
            style: GoogleFonts.caveat(
              fontSize: 30,
              fontWeight: FontWeight.w500,
              color: _kText,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "This feeling will pass. You don't have to do anything right now.",
            textAlign: TextAlign.center,
            style: GoogleFonts.fraunces(
              fontSize: 14,
              fontStyle: FontStyle.italic,
              color: _kTextMuted,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Section 2 — Breathing lantern
// ─────────────────────────────────────────────────────────────────────────

class BreathingLantern extends StatefulWidget {
  /// Shared breath cycle owned by SafeSpaceScreen (also drives the fireflies).
  final Animation<double> cycle;
  const BreathingLantern({super.key, required this.cycle});

  @override
  State<BreathingLantern> createState() => _BreathingLanternState();
}

class _BreathingLanternState extends State<BreathingLantern> {
  double _previousValue = 0.0;
  bool _isInhalePhase = true;

  // The breath cycle is owned by the parent; we just listen for haptic cues
  // and the inhale/exhale label flip.

  @override
  void initState() {
    super.initState();
    widget.cycle.addListener(_onTick);
  }

  void _onTick() {
    final v = widget.cycle.value;
    // Inhale start — controller wrapped from ~1.0 → ~0.0.
    // Stronger pulses (medium / heavy) so they're more reliably felt.
    if (_previousValue > 0.9 && v < 0.1) HapticFeedback.mediumImpact();
    // Exhale start — crossed 0.4. Heavy + a vibrate so the out-breath cue
    // lands even on phones with weak haptic motors.
    if (_previousValue < 0.4 && v >= 0.4) {
      HapticFeedback.heavyImpact();
      HapticFeedback.vibrate();
    }

    final inhaleNow = v < 0.4;
    if (inhaleNow != _isInhalePhase) {
      _isInhalePhase = inhaleNow;
      if (mounted) setState(() {});
    }
    _previousValue = v;
  }

  @override
  void dispose() {
    widget.cycle.removeListener(_onTick);
    super.dispose();
  }

  void _showHapticHint(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        "Each breath is marked by a soft vibration. If you can't feel it, "
        "turn on Vibration & haptics in your phone's Sound settings.",
        style: GoogleFonts.fraunces(color: Colors.white, height: 1.4),
      ),
      backgroundColor: const Color(0xFF2A3540),
      duration: const Duration(seconds: 5),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    // The breath label + a subtle hint that vibration accompanies each breath.
    // The 12 fireflies floating behind the content provide the visual rhythm.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: Text(
              _isInhalePhase ? 'Breathe in… slowly' : 'Breathe out… let it go',
              key: ValueKey(_isInhalePhase),
              textAlign: TextAlign.center,
              style: GoogleFonts.fraunces(fontSize: 15, color: _kTextMuted),
            ),
          ),
          const SizedBox(height: 16),
          // Lets the user know haptics exist + how to enable them if not felt.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _showHapticHint(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.vibration,
                    size: 13, color: _kTextMuted.withValues(alpha: 0.65)),
                const SizedBox(width: 6),
                Text(
                  "Feel the gentle pulse with each breath",
                  style: GoogleFonts.fraunces(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: _kTextMuted.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// _Firefly data class and _FireflyDot renderer removed.
// Fireflies are now self-contained _FixedFirefly widgets anchored to
// screen coordinates in SafeSpaceScreen's root Stack (Layer 3).

// ─────────────────────────────────────────────────────────────────────────
// Reusable iOS-style "Liquid Glass" card
// ─────────────────────────────────────────────────────────────────────────

class _GlassCard extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double radius;
  final double sigma;
  final Color tint;       // base tint behind blur
  final double tintAlpha; // 0..1
  final Widget child;

  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin = const EdgeInsets.symmetric(horizontal: 16),
    this.radius = 20,
    this.sigma = 22,
    this.tint = _kCardBg,   // dark navy — same as old Container colour
    this.tintAlpha = 0.40,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: tintAlpha),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.10),
                width: 0.6,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Section 3 — 5-4-3-2-1 grounding
// ─────────────────────────────────────────────────────────────────────────

class _GroundingCard extends StatefulWidget {
  const _GroundingCard();

  @override
  State<_GroundingCard> createState() => _GroundingCardState();
}

class _GroundingCardState extends State<_GroundingCard> {
  int _step = 0;

  static const _prompts = [
    'Name 5 things you can see',
    'Name 4 things you can touch',
    'Name 3 things you can hear',
    'Name 2 things you can smell',
    'Name 1 thing you can taste',
  ];

  bool get _isLast => _step == _prompts.length - 1;
  bool get _isDone => _step >= _prompts.length;

  void _advance() {
    setState(() {
      if (_step < _prompts.length) _step += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    // When all 5 steps are complete, collapse the card entirely and show
    // a single soft line in its place — less overwhelming in a crisis state.
    if (_isDone) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          'You did it. You are here.',
          textAlign: TextAlign.center,
          style: GoogleFonts.fraunces(
            fontSize: 15,
            fontStyle: FontStyle.italic,
            color: _kTextMuted,
            height: 1.5,
          ),
        ),
      );
    }

    return _GlassCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            _prompts[_step],
            textAlign: TextAlign.center,
            style: GoogleFonts.fraunces(
              fontSize: 18,
              color: _kText,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_prompts.length, (i) {
              final filled = i <= _step;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? _kHelpline : _kPipDim,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _advance,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kAccent, width: 1),
              ),
              child: Text(
                _isLast ? 'Done' : 'Next',
                style: GoogleFonts.fraunces(
                  fontSize: 14,
                  color: _kText,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Section 4 — Comforting anchor (saved memory or fallback)
// ─────────────────────────────────────────────────────────────────────────

class _ComfortAnchor extends StatefulWidget {
  const _ComfortAnchor();

  @override
  State<_ComfortAnchor> createState() => _ComfortAnchorState();
}

class _ComfortAnchorState extends State<_ComfortAnchor> {
  String? _memoryText;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadMemory();
  }

  Future<void> _loadMemory() async {
    String? memory;
    try {
      memory = await MemoryService().getMostRecent();
    } catch (_) {
      // swallow — fall back to default message
    }
    if (!mounted) return;
    setState(() {
      _memoryText = memory;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const SizedBox(height: 80);
    }

    final hasMemory = _memoryText != null && _memoryText!.trim().isNotEmpty;

    return _GlassCard(
      tint: _kCardSofterBg,
      tintAlpha: 0.45,
      child: hasMemory
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Remember this?',
                  style: GoogleFonts.caveat(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: _kText,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _memoryText!,
                  style: GoogleFonts.fraunces(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: _kText,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                // Optional bears illustration — only show if asset present
                Center(
                  child: Image.asset(
                    'assets/illustrations/bears_hug.png',
                    width: 80,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ],
            )
          : Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                'You have made it through every hard day so far. '
                "Including the ones you thought you wouldn't.",
                textAlign: TextAlign.center,
                style: GoogleFonts.fraunces(
                  fontSize: 15,
                  fontStyle: FontStyle.italic,
                  color: _kTextMuted,
                  height: 1.55,
                ),
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Section 5 — Helplines
// ─────────────────────────────────────────────────────────────────────────

class _HelplineSection extends StatelessWidget {
  const _HelplineSection();

  Future<void> _dial(BuildContext context, String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Couldn't open dialler — number is $number"),
              backgroundColor: _kHelpline,
            ),
          );
        }
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Couldn't open dialler — number is $number"),
            backgroundColor: _kHelpline,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12, top: 0),
            child: Text(
              'Talk to someone right now',
              style: GoogleFonts.fraunces(
                fontSize: 15,
                color: _kText,
              ),
            ),
          ),
          _HelplineCard(
            name: 'iCall',
            subtitle: 'Trained counsellors, free',
            number: '9152987821',
            displayNumber: '9152987821',
            onTap: () => _dial(context, '9152987821'),
          ),
          const SizedBox(height: 12),
          _HelplineCard(
            name: 'KIRAN',
            subtitle: '24/7 mental health helpline',
            number: '18005990019',
            displayNumber: '1800-599-0019',
            showTollFreeBadge: true,
            onTap: () => _dial(context, '18005990019'),
          ),
          const SizedBox(height: 12),
          _HelplineCard(
            name: 'Vandrevala',
            subtitle: 'Available 24/7',
            number: '18602662345',
            displayNumber: '1860-2662-345',
            onTap: () => _dial(context, '18602662345'),
          ),
        ],
      ),
    );
  }
}

class _HelplineCard extends StatelessWidget {
  final String name;
  final String subtitle;
  final String number; // used for tel: (digits only)
  final String displayNumber;
  final bool showTollFreeBadge;
  final VoidCallback onTap;

  const _HelplineCard({
    required this.name,
    required this.subtitle,
    required this.number,
    required this.displayNumber,
    required this.onTap,
    this.showTollFreeBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: _GlassCard(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        radius: 16,
        sigma: 18,
        child: Row(
          children: [
            const Icon(Icons.phone_outlined, size: 18, color: _kHelpline),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.fraunces(
                          fontSize: 14,
                          color: _kText,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (showTollFreeBadge) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: _kBadgeBg,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Toll free',
                            style: GoogleFonts.fraunces(
                              fontSize: 9,
                              color: _kText,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.fraunces(
                      fontSize: 11,
                      color: _kTextMuted,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              displayNumber,
              style: GoogleFonts.fraunces(
                fontSize: 13,
                color: _kHelpline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Final note
// ─────────────────────────────────────────────────────────────────────────

class _FinalNote extends StatelessWidget {
  const _FinalNote();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: Text(
        "It's okay to not be okay.",
        textAlign: TextAlign.center,
        style: GoogleFonts.caveat(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: _kTextMuted,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _FixedFirefly — a firefly pinned to a fixed screen position.
//
// Lives in Layer 3 of SafeSpaceScreen's root Stack, OUTSIDE the
// SingleChildScrollView. Scrolling the content never moves it.
//
// Animation is entirely self-contained (own AnimationController).
// Integer frequencies guarantee a seamless loop (sin value at t=0 equals
// sin value at t=1, so there is no jump when the controller wraps around).
// ─────────────────────────────────────────────────────────────────────────────

class _FixedFirefly extends StatefulWidget {
  final double cx;   // centre-X in screen (root Stack) coordinates
  final double cy;   // centre-Y in screen (root Stack) coordinates
  final double size; // core dot diameter
  final int seed;    // deterministic RNG seed — ensures stable positions
  final Animation<double> breath; // shared breath cycle (glow in / dim out)

  const _FixedFirefly({
    required this.cx,
    required this.cy,
    required this.size,
    required this.seed,
    required this.breath,
    super.key,
  });

  @override
  State<_FixedFirefly> createState() => _FixedFireflyState();
}

class _FixedFireflyState extends State<_FixedFirefly>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl; // gentle position drift only
  late final double _driftX;
  late final double _driftY;
  late final double _phaseX;
  late final double _phaseY;
  late final double _breathPhase; // tiny per-firefly offset so it's organic

  // Half-size of the Positioned bounding box (glow max + drift max ≈ 80 pt)
  static const double _extent = 80.0;

  @override
  void initState() {
    super.initState();
    final r      = math.Random(widget.seed);
    _driftX      = 14 + r.nextDouble() * 18;
    _driftY      = 10 + r.nextDouble() * 14;
    _phaseX      = r.nextDouble() * math.pi * 2;
    _phaseY      = r.nextDouble() * math.pi * 2;
    // ±0.04 of the cycle — keeps them near-synced to the breath but not robotic.
    _breathPhase = (r.nextDouble() - 0.5) * 0.08;

    // Varied periods so the fireflies drift (move) out-of-sync. Brightness is
    // driven by the shared breath cycle, not this controller.
    final secs = 8 + (widget.seed % 5); // 8–12 s
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(seconds: secs),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left:   widget.cx - _extent,
      top:    widget.cy - _extent,
      width:  _extent * 2,
      height: _extent * 2,
      child: AnimatedBuilder(
        animation: Listenable.merge([_ctrl, widget.breath]),
        builder: (_, _) {
          final t   = _ctrl.value;
          final pi2 = math.pi * 2;

          final dx = _driftX * math.sin(pi2 * t + _phaseX);
          final dy = _driftY * math.cos(pi2 * t + _phaseY);

          // Glow tracks the breath: bright at the top of the in-breath,
          // dim at the bottom of the out-breath.
          final bt = (widget.breath.value + _breathPhase) % 1.0;
          final breath = breathBrightness(bt < 0 ? bt + 1.0 : bt);
          final brightness = (0.12 + 0.88 * breath).clamp(0.0, 1.0);

          final core   = widget.size * (0.85 + 0.40 * brightness);
          final glow   = widget.size * (2.50 + 5.00 * brightness);
          final glowOp = (0.15 + 0.70 * brightness).clamp(0.0, 1.0);

          return Transform.translate(
            offset: Offset(dx, dy),
            child: Center(
              child: Container(
                width:  core,
                height: core,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kLanternCore.withValues(
                    alpha: brightness.clamp(0.22, 1.0),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color:        _kLanternHalo.withValues(alpha: glowOp),
                      blurRadius:   glow,
                      spreadRadius: glow * 0.25,
                    ),
                    BoxShadow(
                      color:      _kLanternCore.withValues(alpha: glowOp * 0.6),
                      blurRadius: glow * 0.5,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
