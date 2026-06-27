import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/theme_service.dart';
import '../services/user_service.dart';
import '../widgets/memory_wall_preview.dart';
import 'chais_lair_screen.dart';
import 'memory_wall_screen.dart';
import 'safe_space_screen.dart';

typedef OnSwitchTab = void Function(int index);

// ─────────────────────────────────────────────────────────────────────────────
// HomeScreen — bright/dark themed home built from cropped mockup cards.
//
// Layout (top → bottom):
//   1. Hero band — autumn landscape with the cat-figure-on-fence ("Hi" scene)
//   2. Talk to Chai card — taps open ChaisLairScreen. Overlaid with a dynamic
//      "Good evening, {Name}" greeting in Cormorant Garamond SemiBold.
//   3. Memory Wall card — taps open the Memory Wall (Spaces tab).
//   4. Safe Space card — taps open SafeSpaceScreen (panic room).
//   5. "You matter. And you're not alone." pill.
//
// Bright assets switch to dark assets automatically based on ThemeService.
// ─────────────────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  final OnSwitchTab? onSwitchTab;
  const HomeScreen({super.key, this.onSwitchTab});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  String? _name;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    UserService().addListener(_loadName);
    ThemeService().addListener(_onThemeTick);
    _loadName();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    UserService().removeListener(_loadName);
    ThemeService().removeListener(_onThemeTick);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ThemeService().refresh();
    }
  }

  Future<void> _loadName() async {
    final n = await UserService().getName();
    if (!mounted) return;
    setState(() => _name = n);
  }

  void _onThemeTick() {
    if (mounted) setState(() {});
  }

  String _greetingForHour(int h) {
    if (h < 12) return 'Good morning,';
    if (h < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  void _openChai() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ChaisLairScreen()),
      );

  void _openMemory() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const MemoryWallScreen()),
      );

  void _openSafeSpace() => Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const SafeSpaceScreen(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeService().isDark;
    final bg = isDark ? const Color(0xFF0E0F0C) : const Color(0xFFE9D7AA);
    final pillBg =
        isDark ? const Color(0xFF1A1B16) : const Color(0xFFE3CFA0);
    final pillText =
        isDark ? const Color(0xFFD7C496) : const Color(0xFF5A4423);
    final theme = isDark ? 'dark' : 'bright';

    final hour = DateTime.now().hour;
    final greeting = _greetingForHour(hour);
    final username = (_name?.trim().isNotEmpty ?? false) ? _name!.trim() : 'friend';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness:
            isDark ? Brightness.dark : Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: bg,
        // No top SafeArea — the hero bleeds under the status bar.
        body: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Hero band — autumn/night landscape, extends edge-to-edge under
              // the status bar (no rounded corners, no margin).
              AspectRatio(
                aspectRatio: 853 / 470,
                child: Image.asset(
                  'assets/illustrations/home_${theme}_hero.png',
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
                ),
              ),

              const SizedBox(height: 14),

              // Talk to Chai — image + dynamic greeting overlay
              _ChaiCard(
                asset: 'assets/illustrations/home_${theme}_chai.png',
                greeting: greeting,
                username: username,
                isDark: isDark,
                onTap: _openChai,
              ),

              const SizedBox(height: 12),

              // Memory Wall — static art header, then the rotating saved
              // memories live right below it. Tapping either opens the full
              // memory wall.
              _CardImage(
                asset: 'assets/illustrations/home_${theme}_memory.png',
                aspect: 853 / 227,
                radius: 22,
                onTap: _openMemory,
              ),

              const SizedBox(height: 10),

              // Rotating memory preview — auto-hidden when there are no
              // saved memories (showEmpty: false).
              const MemoryWallPreview(
                margin: EdgeInsets.symmetric(horizontal: 14),
              ),

              const SizedBox(height: 12),

              // Safe Space — opens the panic room
              _CardImage(
                asset: 'assets/illustrations/home_${theme}_safe.png',
                aspect: 853 / 246,
                radius: 22,
                onTap: _openSafeSpace,
              ),

              const SizedBox(height: 16),

              // "You matter. And you're not alone." pill
              Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                  decoration: BoxDecoration(
                    color: pillBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🌼  ', style: TextStyle(fontSize: 14)),
                      Text(
                        "You matter. And you're not alone.",
                        style: GoogleFonts.fraunces(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: pillText,
                        ),
                      ),
                      const Text('  🤎', style: TextStyle(fontSize: 14)),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Generic rounded-corner image card with optional tap.
// ─────────────────────────────────────────────────────────────────────────────

class _CardImage extends StatelessWidget {
  final String asset;
  final double aspect;
  final double radius;
  final double horizontalMargin;
  final VoidCallback? onTap;

  const _CardImage({
    required this.asset,
    required this.aspect,
    this.radius = 22,
    this.horizontalMargin = 14,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AspectRatio(
        aspectRatio: aspect,
        child: Image.asset(
          asset,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
        ),
      ),
    );

    final padded = Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalMargin),
      child: image,
    );

    return onTap == null
        ? padded
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: padded,
          );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Talk to Chai card — image background + greeting overlay.
//
// The cropped chai card has its dashed line / empty input box painted out, so
// the greeting sits cleanly between the baked "Talk to Chai" title and the
// baked "Chat with Chai…" subtitle.
//
// Overlay positioning is expressed as fractions of the card's display size:
//   • left:  cardWidth × 0.11   (matches the title's left margin in the art)
//   • top:   cardHeight × 0.32  (between title and subtitle)
//
// Font: Cormorant Garamond SemiBold (greeting) / Bold (username) — warm,
// elegant serif. Colours:
//   • bright theme — #3D2A1F (warm dark brown)
//   • dark theme   — #E8D6A5 (warm cream)
// ─────────────────────────────────────────────────────────────────────────────

class _ChaiCard extends StatelessWidget {
  final String asset;
  final String greeting;
  final String username;
  final bool isDark;
  final VoidCallback onTap;

  const _ChaiCard({
    required this.asset,
    required this.greeting,
    required this.username,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = isDark ? const Color(0xFFE8D6A5) : const Color(0xFF3D2A1F);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: AspectRatio(
            aspectRatio: 853 / 400,
            child: LayoutBuilder(
              builder: (context, c) {
                final cw = c.maxWidth;
                final ch = c.maxHeight;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      asset,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                    ),
                    // Greeting overlay — sits on the cleared band between
                    // "Talk to Chai" title and the "Chat with Chai…" subtitle.
                    Positioned(
                      left: cw * 0.11,
                      top: ch * 0.32,
                      width: cw * 0.50,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            greeting,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.cormorantGaramond(
                              fontSize: cw * 0.052,
                              fontWeight: FontWeight.w800,
                              color: text,
                              height: 1.05,
                              letterSpacing: 0,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.cormorantGaramond(
                              fontSize: cw * 0.068,
                              fontWeight: FontWeight.w700,
                              color: text,
                              height: 1.05,
                              letterSpacing: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
