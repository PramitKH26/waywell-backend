import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/demo_flags.dart';
import '../theme/app_theme.dart';
import '../screens/chais_lair_screen.dart';
import '../screens/home_screen.dart';
import '../screens/journal_screen.dart';
import '../screens/me_screen.dart';
import '../screens/safe_space_screen.dart';
import '../services/theme_service.dart';
import '../services/chat_service.dart';
import '../services/mood_service.dart';
import '../services/notification_service.dart';
import 'mood_checkin_sheet.dart';
import 'panic_button.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MainShell — persistent nav scaffold that wraps all 4 tabs.
// Panic FAB sits above the bottom nav on every screen except PanicRoom.
// ─────────────────────────────────────────────────────────────────────────────

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  Timer? _demoTimer;

  // Cached screen list — created ONCE so widgets keep their state across tab
  // switches and the onSwitchTab callback always targets this State instance.
  // (Previously built inside build(), which re-created all screens on every
  // setState, breaking IndexedStack state preservation and causing BUG 5.)
  late final List<Widget> _screens = [
    HomeScreen(onSwitchTab: (i) => setState(() => _currentIndex = i)),
    const JournalScreen(),
    const MeScreen(),
  ];

  static const List<_NavItem> _items = [
    _NavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: 'Home',
    ),
    _NavItem(
      icon: Icons.eco_outlined,
      activeIcon: Icons.eco_rounded,
      label: 'Spaces',
    ),
    _NavItem(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: 'Profile',
    ),
  ];

  @override
  void initState() {
    super.initState();
    if (kWaywellDemoFlow) {
      _demoTimer = Timer(const Duration(milliseconds: 1600), () {
        if (!mounted) return;
        setState(() => _currentIndex = 2);
      });
    }
    // Mood check-in: show after a short delay so the home screen renders first.
    Timer(const Duration(milliseconds: 900), _maybShowMoodCheckIn);

    // Route based on whether a notification launched us. The payload was
    // captured in main() before runApp(); we consume it once and act.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final payload = NotificationService().consumeLaunchPayload();
      if (payload != null) _handleNotificationPayload(payload);
    });

    // Warm taps (notification tapped while app is already running) route here.
    NotificationService().onWarmTap = (payload) {
      if (!mounted) return;
      _handleNotificationPayload(payload);
    };
  }

  void _handleNotificationPayload(String payload) {
    if (payload == 'checkin') {
      ChatService().setCheckInContext();
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const ChaisLairScreen(),
      ));
    } else if (payload == 'panic') {
      Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const SafeSpaceScreen(),
      ));
    }
  }

  Future<void> _maybShowMoodCheckIn() async {
    if (!mounted) return;
    final should = await MoodService().shouldShowCheckIn();
    if (!should || !mounted) return;
    MoodCheckInSheet.show(context);
  }

  @override
  void dispose() {
    _demoTimer?.cancel();
    NotificationService().onWarmTap = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeService(),
      builder: (context, _) {
        final isDark = ThemeService().isDark;
        return Scaffold(
          backgroundColor:
              isDark ? const Color(0xFF0E0F0C) : AppColors.backgroundCream,
          // Body sits flush above the nav bar (no extendBody — keeps home tight)
          body: IndexedStack(index: _currentIndex, children: _screens),
          floatingActionButton: const PanicButton(),
          floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
          bottomNavigationBar: _BottomBar(
            currentIndex: _currentIndex,
            onTap: (i) => setState(() => _currentIndex = i),
            items: _items,
            isDark: isDark,
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom bar
// ─────────────────────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<_NavItem> items;
  final bool isDark;

  const _BottomBar({
    required this.currentIndex,
    required this.onTap,
    required this.items,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF161712) : const Color(0xFFF7EEDC);
    final border =
        isDark ? const Color(0xFF24251F) : const Color(0xFFE2D4BA);
    final activeColor =
        isDark ? const Color(0xFFE8D6A5) : AppColors.textDark;
    final inactiveColor =
        isDark ? const Color(0xFF7E7561) : AppColors.textSecondary;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: border, width: 1)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(items.length, (i) {
                    final item = items[i];
                    final selected = i == currentIndex;
                    return SizedBox(
                      width: 66,
                      child: InkWell(
                        onTap: () => onTap(i),
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              selected ? item.activeIcon : item.icon,
                              size: 24,
                              color: selected ? activeColor : inactiveColor,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.label,
                              style: GoogleFonts.nunito(
                                fontSize: 12,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                color: selected ? activeColor : inactiveColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(width: 96),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}
