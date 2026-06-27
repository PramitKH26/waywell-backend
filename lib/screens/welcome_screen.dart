import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/demo_flags.dart';
import '../services/user_service.dart';
import '../widgets/bottom_nav.dart';
import 'nickname_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WelcomeScreen
//
// The new designer artwork (1086 × 1448) bakes the "Hi / Welcome back /
// A safe space for your mind and heart" text into the image.  We render the
// artwork edge-to-edge, then overlay a real Flutter "Get started" pill near
// the bottom — the new mockup doesn't include one baked in.
//
// Layout strategy:
//   • BoxFit.cover with top-centred alignment so the title block and the cat
//     remain visible regardless of phone aspect ratio.
//   • Soft cream fade at the bottom for button legibility.
//   • 600 ms fade-in entrance.
//   • 96 % scale-down feedback on the button.
// ─────────────────────────────────────────────────────────────────────────────

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeIn;
  bool _didNavigate = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
      reverseDuration: const Duration(milliseconds: 250),
    );
    _fadeIn = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();

    // Welcome is shown on every launch now (no once-per-day skip).

    if (kWaywellDemoFlow) {
      Future.delayed(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        _onGetStarted();
      });
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _onGetStarted() async {
    if (_didNavigate) return;
    _didNavigate = true;
    if (!mounted) return;

    // Show the nickname screen only on the very first run; otherwise go
    // straight to the app. Once seen (set OR skipped), never ask again.
    final showNickname = await UserService().shouldShowNickname();
    await UserService().markNicknameSeen();
    if (!mounted) return;

    await _fadeController.reverse();
    if (!mounted) return;

    Widget destination =
        showNickname ? const NicknameScreen() : const MainShell();

    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 700),
        pageBuilder: (ctx, a1, a2) => destination,
        transitionsBuilder: (ctx, animation, a2, child) {
          final fade  = CurvedAnimation(parent: animation, curve: Curves.easeOut);
          final slide = Tween<Offset>(
            begin: const Offset(0, 0.03),
            end:   Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));
          return FadeTransition(
            opacity: fade,
            child: SlideTransition(position: slide, child: child),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFE9DCBC),
        body: FadeTransition(
          opacity: _fadeIn,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Full-bleed watercolor scene — bias the cover crop towards the
              // right so the cat-on-stairs stays in view, with a small upward
              // bias so the "Hi / Welcome back" title block is still visible.
              Image.asset(
                'assets/illustrations/welcome_full.png',
                fit: BoxFit.cover,
                alignment: const Alignment(0.65, -0.25),
                filterQuality: FilterQuality.high,
              ),

              // Soft cream fade at the bottom — gives the pill button a clean
              // surface to sit on without distracting from the artwork.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 220,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFFE9DCBC).withValues(alpha: 0.0),
                        const Color(0xFFE9DCBC).withValues(alpha: 0.85),
                      ],
                    ),
                  ),
                ),
              ),

              // "Get started" pill — anchored bottom-centre, above the home indicator
              SafeArea(
                top: false,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 28),
                    child: _GetStartedButton(onTap: _onGetStarted),
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

// ─────────────────────────────────────────────────────────────────────────────
// "Get started" pill button
// ─────────────────────────────────────────────────────────────────────────────

class _GetStartedButton extends StatefulWidget {
  final VoidCallback onTap;
  const _GetStartedButton({required this.onTap});

  @override
  State<_GetStartedButton> createState() => _GetStartedButtonState();
}

class _GetStartedButtonState extends State<_GetStartedButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          width: 240,
          height: 60,
          decoration: BoxDecoration(
            color: const Color(0xFF3D2817),
            borderRadius: BorderRadius.circular(30),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Get started',
                style: GoogleFonts.fraunces(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFFF5EAD3),
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.arrow_forward_rounded,
                color: Color(0xFFF5EAD3),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
