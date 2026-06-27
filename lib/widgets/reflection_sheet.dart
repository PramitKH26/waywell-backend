import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/identity_service.dart';
import '../services/mood_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ReflectionSheet — "Did anything shift?" after a meaningful interaction.
//
// Show after: Chat Session, Story Session, Safe Space Session.
// NOT after every screen.
// ─────────────────────────────────────────────────────────────────────────────

const _kOptions = [
  'A little lighter',
  'More understood',
  'More hopeful',
  'Still overwhelmed',
  'No change',
];

class ReflectionSheet extends StatefulWidget {
  final String beforeMood;
  const ReflectionSheet({super.key, required this.beforeMood});

  /// Show the reflection sheet. Returns the chosen reflection string, or null.
  static Future<String?> show(BuildContext context, String beforeMood) {
    return showModalBottomSheet<String>(
      context:            context,
      isScrollControlled: true,
      backgroundColor:    Colors.transparent,
      builder: (_) => ReflectionSheet(beforeMood: beforeMood),
    );
  }

  @override
  State<ReflectionSheet> createState() => _ReflectionSheetState();
}

class _ReflectionSheetState extends State<ReflectionSheet> {
  String? _selected;

  Future<void> _done() async {
    if (_selected == null) {
      Navigator.of(context).pop(null);
      return;
    }
    final userId = await IdentityService().getUserId();
    MoodService().logReflection(widget.beforeMood, _selected!, userId);
    if (mounted) Navigator.of(context).pop(_selected);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFDF6E8),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        24, 20, 24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD4C4A8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),

          Text(
            'Did anything shift?',
            style: GoogleFonts.fraunces(
              fontSize:   24,
              fontWeight: FontWeight.w400,
              color:      const Color(0xFF3D2817),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'No right answer — just noticing.',
            style: GoogleFonts.fraunces(
              fontSize: 14,
              color:    const Color(0xFF9C8060),
            ),
          ),
          const SizedBox(height: 20),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kOptions.map((opt) {
              final sel = _selected == opt;
              return GestureDetector(
                onTap: () => setState(() => _selected = opt),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: sel
                        ? const Color(0xFF3D2817).withValues(alpha: 0.10)
                        : const Color(0xFFF0E6D0),
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(
                      color: sel
                          ? const Color(0xFF3D2817)
                          : const Color(0xFFD4C4A8),
                      width: sel ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    opt,
                    style: GoogleFonts.fraunces(
                      fontSize:   15,
                      fontWeight: sel
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: const Color(0xFF3D2817),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 28),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _done,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF3D2817),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(50),
                ),
              ),
              child: Text(
                _selected != null ? 'Done' : 'Skip',
                style: GoogleFonts.fraunces(
                  fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
