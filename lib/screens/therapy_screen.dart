import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'chais_lair_screen.dart';

class TherapyScreen extends StatelessWidget {
  const TherapyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5EAD3),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              _buildChaiIntro(context),
              const SizedBox(height: 16),
              _buildFeatureGrid(context),
              const SizedBox(height: 16),
              _buildHelplines(),
              const SizedBox(height: 16),
              _buildBottomStrip(context),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Therapy',
            style: GoogleFonts.caveat(
              fontSize: 32,
              color: const Color(0xFF3D2817),
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            'Professional support, whenever you need it.',
            style: GoogleFonts.fraunces(
              fontSize: 14,
              color: const Color(0xFF9AA8B8),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChaiIntro(BuildContext context) {
    return GestureDetector(
      onTap: () => _openChaiChat(context),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFFCDD9C0),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          children: [
            // Speech bubble
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFFAF5E8),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFFD4C4A0).withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: GoogleFonts.fraunces(
                          fontSize: 15,
                          color: const Color(0xFF3D2817),
                          height: 1.5,
                        ),
                        children: const [
                          TextSpan(text: 'Hi, I\'m '),
                          TextSpan(
                            text: 'Chai.',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF3D5A2A),
                            ),
                          ),
                          TextSpan(
                            text: '\nI\'m here to support you on your journey.',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('🌿', style: TextStyle(fontSize: 20)),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Main Chai illustration
            Image.asset(
              'assets/illustrations/chai_center.png',
              height: 180,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Image.asset(
                'assets/illustrations/chai_main.png',
                height: 180,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                    const Text('🐱', style: TextStyle(fontSize: 80)),
              ),
            ),

            const SizedBox(height: 12),

            // Nameplate
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFAF0DC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFD4C4A0),
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Chai',
                    style: GoogleFonts.caveat(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF3D2817),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('🌿', style: TextStyle(fontSize: 14)),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Your therapy companion',
              style: GoogleFonts.fraunces(
                fontSize: 12,
                color: const Color(0xFF6B4F36),
                fontStyle: FontStyle.italic,
              ),
            ),

            const SizedBox(height: 16),

            // Talk to Chai CTA
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF4A7C59),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Center(
                child: Text(
                  'Talk to Chai',
                  style: GoogleFonts.fraunces(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureGrid(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
        children: [
          _buildFeatureCard(
            context: context,
            asset: 'chai_booking.png',
            title: 'Manage Bookings',
            subtitle: 'I\'ll help you find the right time.',
            isLive: false,
            badge: 'Coming soon',
            onTap: () => _showComingSoon(
              context,
              'Booking',
              'We\'re setting up connections with counsellors. '
              'For now, iCall is available at 9152987821.',
            ),
          ),
          _buildFeatureCard(
            context: context,
            asset: 'chai_progress.png',
            title: 'Track Progress',
            subtitle: 'We\'ll celebrate every small step.',
            isLive: false,
            badge: 'Coming soon',
            onTap: () => _showComingSoon(
              context,
              'Progress Tracking',
              'Weekly mood insights are coming. For now your '
              'Memory Wall tracks the good moments.',
            ),
          ),
          _buildFeatureCard(
            context: context,
            asset: 'chai_support.png',
            title: 'Emotional Support',
            subtitle: 'I\'m always here to listen.',
            isLive: true,
            badge: 'Available now',
            onTap: () => _openChaiChat(context),
          ),
          _buildFeatureCard(
            context: context,
            asset: 'chai_reminder.png',
            title: 'Gentle Reminders',
            subtitle: 'I\'ll nudge you with kindness.',
            isLive: false,
            badge: 'Coming soon',
            onTap: () => _showComingSoon(
              context,
              'Reminders',
              'Set your daily check-in time in your profile — '
              'that\'s live now.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard({
    required BuildContext context,
    required String asset,
    required String title,
    required String subtitle,
    required bool isLive,
    required String badge,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isLive
                ? const Color(0xFF4A7C59).withValues(alpha: 0.3)
                : const Color(0xFFE8D5B7),
            width: isLive ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Center(
                child: Image.asset(
                  'assets/illustrations/$asset',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Text(
                    _fallbackEmoji(asset),
                    style: const TextStyle(fontSize: 48),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isLive
                    ? const Color(0xFF4A7C59).withValues(alpha: 0.1)
                    : const Color(0xFFF5EAD3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                badge,
                style: GoogleFonts.fraunces(
                  fontSize: 10,
                  color: isLive
                      ? const Color(0xFF4A7C59)
                      : const Color(0xFF9AA8B8),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: GoogleFonts.fraunces(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF3D2817),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: GoogleFonts.fraunces(
                fontSize: 11,
                color: const Color(0xFF9AA8B8),
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fallbackEmoji(String asset) {
    if (asset.contains('booking'))  return '📅';
    if (asset.contains('progress')) return '📋';
    if (asset.contains('support'))  return '🫂';
    if (asset.contains('reminder')) return '💛';
    return '🐱';
  }

  Widget _buildHelplines() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFFAF5E8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE8D5B7)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Need help right now?',
              style: GoogleFonts.fraunces(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF3D2817),
              ),
            ),
            const SizedBox(height: 12),
            _helplineRow('iCall', 'Trained counsellors, free', '9152987821'),
            const SizedBox(height: 8),
            _helplineRow(
              'KIRAN Helpline', 'Government mental health', '1800-599-0019',
              isTollFree: true,
            ),
            const SizedBox(height: 8),
            _helplineRow(
              'Vandrevala Foundation', '24/7 crisis support', '1860-2662-345',
            ),
          ],
        ),
      ),
    );
  }

  Widget _helplineRow(
    String name,
    String subtitle,
    String number, {
    bool isTollFree = false,
  }) {
    return GestureDetector(
      onTap: () => launchUrl(Uri.parse('tel:$number')),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFE8EFE0),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.phone_outlined,
                color: Color(0xFF4A7C59), size: 20),
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
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF3D2817),
                        ),
                      ),
                      if (isTollFree) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4A7C59),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Toll free',
                            style: GoogleFonts.fraunces(
                              fontSize: 9,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.fraunces(
                      fontSize: 12,
                      color: const Color(0xFF6B4F36),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              number,
              style: GoogleFonts.fraunces(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF4A7C59),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomStrip(BuildContext context) {
    return GestureDetector(
      onTap: () => _openChaiChat(context),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFE8EFE0),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF4A7C59).withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            Image.asset(
              'assets/illustrations/chai_peeking.png',
              height: 72,
              width: 72,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Text('🐱', style: TextStyle(fontSize: 48)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'You\'re not alone.',
                    style: GoogleFonts.caveat(
                      fontSize: 22,
                      color: const Color(0xFF3D2817),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    'I\'ve got your back. 🌿',
                    style: GoogleFonts.fraunces(
                      fontSize: 14,
                      color: const Color(0xFF6B4F36),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Color(0xFF4A7C59),
            ),
          ],
        ),
      ),
    );
  }

  void _openChaiChat(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChaisLairScreen()),
    );
  }

  void _showComingSoon(
    BuildContext context,
    String feature,
    String message,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(28),
        decoration: const BoxDecoration(
          color: Color(0xFFF5EAD3),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE8D5B7),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              feature,
              style: GoogleFonts.caveat(
                fontSize: 24,
                color: const Color(0xFF3D2817),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: GoogleFonts.fraunces(
                fontSize: 14,
                color: const Color(0xFF5C4A32),
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () {
                Navigator.pop(context);
                _openChaiChat(context);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF4A7C59),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Center(
                  child: Text(
                    'Talk to Chai instead',
                    style: GoogleFonts.fraunces(
                      fontSize: 15,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Close',
                style: GoogleFonts.fraunces(
                  color: const Color(0xFF9AA8B8),
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
