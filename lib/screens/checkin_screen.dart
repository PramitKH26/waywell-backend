import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import 'chat_screen.dart';
import 'safe_space_screen.dart';

class CheckinScreen extends StatelessWidget {
  const CheckinScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: const Color(0xFFF2E9FB),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF7F1FF),
              Color(0xFFEADFF8),
              Color(0xFFF2E9FB),
            ],
          ),
        ),
        child: ListView(
          padding: EdgeInsets.only(top: topInset, bottom: 120),
          children: [
            _TherapyHero(
              onMessageTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ChatScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            _SupportCard(
              icon: Icons.person_search_rounded,
              title: 'Find a therapist',
              subtitle: 'Match with someone who fits your pace.',
              accent: const Color(0xFF7155A8),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const _TherapyStubScreen(
                      title: 'Find a therapist',
                      subtitle: 'Choose the style of support that feels right.',
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _SupportCard(
              icon: Icons.calendar_month_rounded,
              title: 'Book a session',
              subtitle: 'Reserve a calm time that fits your day.',
              accent: const Color(0xFF6A81C2),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const _TherapyStubScreen(
                      title: 'Book a session',
                      subtitle: 'Pick a time that feels easy and safe.',
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _SupportCard(
              icon: Icons.health_and_safety_rounded,
              title: 'Panic support',
              subtitle: 'Open immediate help if things feel heavy.',
              accent: const Color(0xFFE07E6C),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SafeSpaceScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _SupportCard(
              icon: Icons.menu_book_rounded,
              title: 'Session notes',
              subtitle: 'Capture the words that matter most.',
              accent: const Color(0xFF8A6A49),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const _TherapyStubScreen(
                      title: 'Session notes',
                      subtitle: 'A gentle place for your reflections.',
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TherapyHero extends StatelessWidget {
  final VoidCallback onMessageTap;

  const _TherapyHero({required this.onMessageTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 312,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFE1D2F4),
              Color(0xFFD5C2EC),
              Color(0xFFC5ADE5),
            ],
          ),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: const Color(0xFFD4C0E8)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x11000000),
              blurRadius: 22,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -10,
              top: 0,
              bottom: 0,
              width: 194,
              child: Image.asset(
                'assets/illustrations/therapy_chair.png',
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
            Positioned(
              right: 10,
              top: 10,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5EDFF),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFD9CAE8)),
                ),
                child: const Icon(
                  Icons.chat_bubble_rounded,
                  color: Color(0xFF73559F),
                  size: 24,
                ),
              ),
            ),
            Positioned(
              left: 18,
              top: 18,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFF6EEFF),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFD9CAE8)),
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  color: Color(0xFF73559F),
                  size: 22,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 86, 146, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Talk to a therapist',
                    style: GoogleFonts.caveat(
                      fontSize: 36,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF4E356A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'A calm space for support,\nreflection, and care.',
                    style: GoogleFonts.nunito(
                      fontSize: 15,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF4E356A),
                    ),
                  ),
                  const Spacer(),
                  _TherapyButton(
                    label: 'Message now',
                    backgroundColor: const Color(0xFF5D458B),
                    onTap: onMessageTap,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  const _SupportCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            height: 98,
            decoration: BoxDecoration(
              color: const Color(0xFFF8F2FF),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFDCCBF1)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x10000000),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: accent,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.caveat(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF4E356A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: GoogleFonts.nunito(
                          fontSize: 12,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF6C5A81),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: accent,
                  size: 28,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TherapyButton extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final VoidCallback onTap;

  const _TherapyButton({
    required this.label,
    required this.backgroundColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.chat_bubble_rounded,
                size: 18,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.nunito(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TherapyStubScreen extends StatelessWidget {
  final String title;
  final String subtitle;

  const _TherapyStubScreen({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundCream,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          title,
          style: GoogleFonts.caveat(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: AppColors.textDark,
          ),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(
              fontSize: 18,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
        ),
      ),
    );
  }
}
