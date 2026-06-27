import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../screens/safe_space_screen.dart';

class PanicButton extends StatelessWidget {
  const PanicButton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 68,
      height: 68,
      child: FloatingActionButton(
        heroTag: 'panic-button',
        onPressed: () {
          Navigator.of(context).push(
            CupertinoPageRoute(
              fullscreenDialog: true,
              builder: (_) => const SafeSpaceScreen(),
            ),
          );
        },
        backgroundColor: AppColors.panicRed,
        foregroundColor: AppColors.white,
        elevation: 9,
        highlightElevation: 10,
        shape: const CircleBorder(),
        // Heart with a protective shield overlay
        child: const _ShieldHeart(),
      ),
    );
  }
}

/// Two-layer icon: shield behind, heart in front.
class _ShieldHeart extends StatelessWidget {
  const _ShieldHeart();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: const [
        Icon(Icons.shield_rounded, size: 30, color: Colors.white),
        Positioned(
          bottom: 6,
          child: Icon(Icons.favorite_rounded, size: 14, color: Color(0xFFE24B4A)),
        ),
      ],
    );
  }
}
