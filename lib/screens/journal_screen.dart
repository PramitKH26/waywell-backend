import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/theme_service.dart';

/// "Spaces" tab landing.
///
/// Memory Wall lives on the Home screen now (with rotating previews), so
/// this tab is intentionally a quiet placeholder until new spaces are added.
class JournalScreen extends StatelessWidget {
  const JournalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeService(),
      builder: (context, _) {
        final isDark = ThemeService().isDark;
        final bg = isDark ? const Color(0xFF0E0F0C) : const Color(0xFFE9D7AA);
        final title =
            isDark ? const Color(0xFFE8D6A5) : const Color(0xFF3D2A1F);
        final subtitle = isDark
            ? const Color(0xFF9C8E6F)
            : const Color(0xFF6B5230);
        return Scaffold(
          backgroundColor: bg,
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.eco_rounded, size: 56, color: title),
                    const SizedBox(height: 16),
                    Text(
                      'Spaces',
                      style: GoogleFonts.cormorantGaramond(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        color: title,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'New spaces are coming soon.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.fraunces(
                        fontSize: 15,
                        fontStyle: FontStyle.italic,
                        color: subtitle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
