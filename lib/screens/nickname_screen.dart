import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/notification_service.dart';
import '../services/user_service.dart';
import '../widgets/bottom_nav.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NicknameScreen
//
// Shown exactly once: after Get Started, only when no name is set.
// Asks "What should we call you?" — max 20 chars.
// Skippable — anonymous use is intentional.
// ─────────────────────────────────────────────────────────────────────────────

class NicknameScreen extends StatefulWidget {
  const NicknameScreen({super.key});

  @override
  State<NicknameScreen> createState() => _NicknameScreenState();
}

class _NicknameScreenState extends State<NicknameScreen>
    with SingleTickerProviderStateMixin {
  final _ctrl  = TextEditingController();
  final _focus = FocusNode();
  bool _saving = false;

  late final AnimationController _fadeCtrl;
  late final Animation<double>   _fadeIn;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeIn = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();

    // Auto-show keyboard after entrance animation.
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _continue({bool skip = false}) async {
    if (_saving) return;
    setState(() => _saving = true);
    final name = _ctrl.text.trim();
    if (!skip && name.isNotEmpty) {
      await UserService().setName(name);
    }
    // Now we've earned a little trust — ask for notifications so the daily
    // check-in (which the user can configure in Me) can actually fire.
    await NotificationService().requestPermission();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (context, a1, a2) => const MainShell(),
        transitionsBuilder: (_, animation, _, child) {
          final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);
          return FadeTransition(opacity: fade, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor:          Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF0E2C2),
        body: FadeTransition(
          opacity: _fadeIn,
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(28, 48, 28, bottom + 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Text(
                    'What should\nwe call you?',
                    style: GoogleFonts.fraunces(
                      fontSize:   36,
                      fontWeight: FontWeight.w500,
                      color:      const Color(0xFF3D2817),
                      height:     1.15,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Just a nickname — no account needed.',
                    style: GoogleFonts.fraunces(
                      fontSize: 15,
                      color:    const Color(0xFF6B4F36),
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Input field
                  Container(
                    decoration: BoxDecoration(
                      color:        Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFB0957A),
                        width: 1,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 4),
                    child: TextField(
                      controller:    _ctrl,
                      focusNode:     _focus,
                      maxLength:     20,
                      textCapitalization: TextCapitalization.words,
                      style: GoogleFonts.fraunces(
                        fontSize:   22,
                        color:      const Color(0xFF3D2817),
                      ),
                      decoration: InputDecoration(
                        border:      InputBorder.none,
                        hintText:    'e.g. Arjun',
                        counterText: '',
                        hintStyle: GoogleFonts.fraunces(
                          fontSize: 22,
                          color:    const Color(0xFFB0957A),
                        ),
                      ),
                      onSubmitted: (_) => _continue(),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Continue button
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _ctrl,
                    builder: (context, val, child) {
                      final hasText = val.text.trim().isNotEmpty;
                      return GestureDetector(
                        onTap: hasText ? _continue : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          height:  58,
                          decoration: BoxDecoration(
                            color: hasText
                                ? const Color(0xFF3D2817)
                                : const Color(0xFFB0957A),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          alignment: Alignment.center,
                          child: _saving
                              ? const SizedBox(
                                  width: 22, height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation(Colors.white),
                                  ),
                                )
                              : Text(
                                  'Continue',
                                  style: GoogleFonts.fraunces(
                                    fontSize:   17,
                                    fontWeight: FontWeight.w500,
                                    color:      Colors.white,
                                  ),
                                ),
                        ),
                      );
                    },
                  ),

                  const Spacer(),

                  // Skip link
                  Center(
                    child: GestureDetector(
                      onTap: () => _continue(skip: true),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Skip for now',
                          style: GoogleFonts.fraunces(
                            fontSize:  14,
                            color:     const Color(0xFF6B4F36),
                            decoration: TextDecoration.underline,
                            decorationColor: const Color(0xFF6B4F36),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
