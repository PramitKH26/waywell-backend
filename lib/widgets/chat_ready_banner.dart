import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/chat_service.dart';
import '../screens/chat_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ChatReadyBanner
//
// A transparent overlay that lives in the MaterialApp.builder layer (above
// the entire navigator stack).  It listens to ChatService and slides a warm-
// cream card down from the top whenever hasUnreadResponse is true.
//
// Hidden automatically when ChatScreen is open (ChatScreen.initState calls
// markAsRead() which clears the flag).
//
// Animation: spring-bounce slide-in from above, quick fade-out on dismiss.
// ─────────────────────────────────────────────────────────────────────────────

class ChatReadyBanner extends StatefulWidget {
  final Widget child;
  const ChatReadyBanner({super.key, required this.child});

  @override
  State<ChatReadyBanner> createState() => _ChatReadyBannerState();
}

class _ChatReadyBannerState extends State<ChatReadyBanner>
    with SingleTickerProviderStateMixin {
  final _svc = ChatService();
  late final AnimationController _ctrl;
  late final Animation<Offset>   _slide;
  late final Animation<double>   _fade;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    // Elastic spring on enter, straight ease-out on exit
    _slide = Tween<Offset>(
      begin: const Offset(0, -1.5),
      end:   Offset.zero,
    ).animate(CurvedAnimation(
      parent: _ctrl,
      curve:      Curves.elasticOut,
      reverseCurve: Curves.easeIn,
    ));
    _fade = CurvedAnimation(
      parent: _ctrl,
      curve:      Curves.easeIn,
      reverseCurve: Curves.easeOut,
    );
    _svc.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _svc.removeListener(_onServiceUpdate);
    _ctrl.dispose();
    super.dispose();
  }

  void _onServiceUpdate() {
    if (!mounted) return;
    final want = _svc.hasUnreadResponse;
    if (want == _showing) return;
    setState(() => _showing = want);
    if (want) {
      _ctrl.forward(from: 0.0);
    } else {
      _ctrl.reverse();
    }
  }

  void _onTap() {
    _svc.markAsRead();
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ChatScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // padding.top = status-bar height.
    // We're in the MaterialApp.builder layer (above SafeArea/Scaffold),
    // so we position relative to the physical screen top.
    final topPad = MediaQuery.of(context).padding.top;

    return Stack(
      children: [
        widget.child,
        if (_showing || _ctrl.isAnimating)
          Positioned(
            top:   topPad + 10,
            left:  16,
            right: 16,
            child: SlideTransition(
              position: _slide,
              child: FadeTransition(
                opacity: _fade,
                child: _BannerCard(onTap: _onTap),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BannerCard — the visible pill
// ─────────────────────────────────────────────────────────────────────────────

class _BannerCard extends StatelessWidget {
  final VoidCallback onTap;
  const _BannerCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0xFFEDE0C8),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: const Color(0xFF6B3A2A).withValues(alpha: 0.35),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              // Leaf avatar
              Container(
                width:  36,
                height: 36,
                decoration: BoxDecoration(
                  color:        const Color(0xFF4A7C59),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.eco_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              // Text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Your companion replied',
                      style: GoogleFonts.fraunces(
                        fontSize:   14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF3D2817),
                      ),
                    ),
                    Text(
                      'Tap to read',
                      style: GoogleFonts.fraunces(
                        fontSize: 12,
                        color: const Color(0xFF6B4F36),
                      ),
                    ),
                  ],
                ),
              ),
              // Arrow
              Icon(
                Icons.arrow_forward_ios_rounded,
                size:  14,
                color: const Color(0xFF6B3A2A).withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
