import 'package:flutter/material.dart';

import '../services/identity_service.dart';
import '../services/mood_service.dart';

/// Mood check-in popup — the entire visual is `popup_card.png` (a clean crop
/// of the original mood.png mockup). Invisible tap zones sit on top of each
/// drawn chip, the Continue button, the X close, and Maybe later.

// popup_card.png is 1105 × 940 px. Fractions below are derived from pixel
// sweeps of that image (see commit message).
const double _kAspect = 1105 / 940;

class _Chip {
  final String label;
  final double left, top, width, height;
  const _Chip(this.label, this.left, this.top, this.width, this.height);
}

// Rects derived by pixel-sweeping popup_card.png. Numbers were nudged in a
// few px so the selection ring sits INSIDE the drawn chip outline rather
// than flaring beyond it.
const List<_Chip> _kChips = [
  _Chip('Calm',        0.078, 0.445, 0.250, 0.085),
  _Chip('Hopeful',     0.360, 0.445, 0.265, 0.085),
  _Chip('Tired',       0.665, 0.445, 0.260, 0.085),
  _Chip('Stressed',    0.120, 0.572, 0.275, 0.085),
  _Chip('Overwhelmed', 0.420, 0.572, 0.390, 0.085),
  _Chip('Lonely',      0.120, 0.672, 0.275, 0.085),
];

// Continue button (filled brown pill)
const _kContinueRect = Rect.fromLTWH(0.062, 0.795, 0.875, 0.108);
// Maybe later text link
const _kMaybeLaterRect = Rect.fromLTWH(0.370, 0.930, 0.255, 0.050);
// X close (top-right white circle)
const _kCloseRect = Rect.fromLTWH(0.890, 0.020, 0.090, 0.080);

class MoodCheckInSheet extends StatefulWidget {
  const MoodCheckInSheet({super.key});

  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context:            context,
      barrierColor:       Colors.black.withValues(alpha: 0.55),
      barrierDismissible: true,
      builder:            (_) => const MoodCheckInSheet(),
    );
  }

  @override
  State<MoodCheckInSheet> createState() => _MoodCheckInSheetState();
}

class _MoodCheckInSheetState extends State<MoodCheckInSheet> {
  String? _selected;

  Future<void> _confirm() async {
    if (_selected == null) return;
    final userId = await IdentityService().getUserId();
    await MoodService().logMood(_selected!, userId);
    if (mounted) Navigator.of(context).pop(_selected);
  }

  Future<void> _dismiss() async {
    await MoodService().markDismissed();
    if (mounted) Navigator.of(context).pop(null);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor:   Colors.transparent,
      // Push the popup down toward the bottom of the screen by giving it a
      // large top inset and a small bottom inset.
      insetPadding:      const EdgeInsets.fromLTRB(16, 220, 16, 40),
      alignment:         Alignment.bottomCenter,
      elevation:         0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: AspectRatio(
        aspectRatio: _kAspect,
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            final h = c.maxHeight;
            return ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Stack(
                children: [
                  // The image IS the popup.
                  Positioned.fill(
                    child: Image.asset(
                      'assets/illustrations/popup_card.png',
                      fit: BoxFit.fill,
                    ),
                  ),

                  // Chip tap zones + selection ring
                  for (final chip in _kChips)
                    Positioned(
                      left:   chip.left   * w,
                      top:    chip.top    * h,
                      width:  chip.width  * w,
                      height: chip.height * h,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _selected = chip.label),
                        // Padding insets the ring so it draws INSIDE the
                        // chip outline rather than outside it.
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(50),
                              border: Border.all(
                                color: _selected == chip.label
                                    ? const Color(0xFF3D2817)
                                    : Colors.transparent,
                                width: 1.6,
                              ),
                              color: _selected == chip.label
                                  ? const Color(0x1F3D2817)
                                  : Colors.transparent,
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Continue button
                  Positioned(
                    left:   _kContinueRect.left   * w,
                    top:    _kContinueRect.top    * h,
                    width:  _kContinueRect.width  * w,
                    height: _kContinueRect.height * h,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _selected != null ? _confirm : null,
                      child: const SizedBox.expand(),
                    ),
                  ),

                  // Maybe later
                  Positioned(
                    left:   _kMaybeLaterRect.left   * w,
                    top:    _kMaybeLaterRect.top    * h,
                    width:  _kMaybeLaterRect.width  * w,
                    height: _kMaybeLaterRect.height * h,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _dismiss,
                      child: const SizedBox.expand(),
                    ),
                  ),

                  // X close
                  Positioned(
                    left:   _kCloseRect.left   * w,
                    top:    _kCloseRect.top    * h,
                    width:  _kCloseRect.width  * w,
                    height: _kCloseRect.height * h,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _dismiss,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
