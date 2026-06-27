import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../screens/memory_wall_screen.dart';
import '../services/memory_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MemoryWallPreview
//
// • If no memories exist: hidden on home (showEmpty=false), empty-state card
//   on Spaces (showEmpty=true).
// • If memories exist: rotates through them every ~2.5 minutes, starting on a
//   random one so each app open feels fresh.
// • Adapts size to content — text card for written notes, photo card with the
//   image's native aspect ratio for photo notes.
// ─────────────────────────────────────────────────────────────────────────────

const _kRotationInterval = Duration(seconds: 150);

class MemoryWallPreview extends StatefulWidget {
  final EdgeInsets margin;
  final bool       showEmpty;

  const MemoryWallPreview({
    super.key,
    this.margin    = const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
    this.showEmpty = false,
  });

  @override
  State<MemoryWallPreview> createState() => _MemoryWallPreviewState();
}

class _MemoryWallPreviewState extends State<MemoryWallPreview> {
  List<Memory> _memories = [];
  int          _index    = 0;
  bool         _loaded   = false;
  Timer?       _rotateTimer;

  @override
  void initState() {
    super.initState();
    MemoryService().addListener(_reload);
    _load();
  }

  @override
  void dispose() {
    MemoryService().removeListener(_reload);
    _rotateTimer?.cancel();
    super.dispose();
  }

  void _reload() => _load();

  Future<void> _load() async {
    try {
      final memories = await MemoryService().getMemories();
      if (!mounted) return;
      setState(() {
        _memories = memories;
        _loaded   = true;
        if (memories.isNotEmpty) {
          // Random starting index so app open isn't static.
          _index = Random().nextInt(memories.length);
        }
      });
      _restartRotation();
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  void _restartRotation() {
    _rotateTimer?.cancel();
    if (_memories.length < 2) return;
    _rotateTimer = Timer.periodic(_kRotationInterval, (_) {
      if (!mounted || _memories.isEmpty) return;
      setState(() => _index = (_index + 1) % _memories.length);
    });
  }

  void _advanceManually() {
    if (_memories.length < 2) return;
    setState(() => _index = (_index + 1) % _memories.length);
    _restartRotation();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    if (_memories.isEmpty && !widget.showEmpty) return const SizedBox.shrink();
    if (_memories.isEmpty) return _EmptyMemoryCard(margin: widget.margin);

    final memory = _memories[_index.clamp(0, _memories.length - 1)];

    return Padding(
      padding: widget.margin,
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MemoryWallScreen()),
        ),
        onLongPress: _advanceManually,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          switchInCurve:  Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end:   Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          child: memory.isPhoto
              ? _PhotoMemoryCard(
                  key:      ValueKey('photo_${memory.id}'),
                  memory:   memory,
                  position: _positionLabel(),
                )
              : _TextMemoryCard(
                  key:      ValueKey('text_${memory.id}'),
                  memory:   memory,
                  position: _positionLabel(),
                ),
        ),
      ),
    );
  }

  String? _positionLabel() {
    if (_memories.length < 2) return null;
    return '${_index + 1} / ${_memories.length}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Text memory card — parchment, italic quote
// ─────────────────────────────────────────────────────────────────────────────

class _TextMemoryCard extends StatelessWidget {
  final Memory  memory;
  final String? position;

  const _TextMemoryCard({super.key, required this.memory, this.position});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _cardDecoration,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _CardHeader(position: position),
          const SizedBox(height: 14),
          _SubLabel(),
          const SizedBox(height: 10),
          Text(
            '"${memory.text}"',
            style: GoogleFonts.fraunces(
              fontSize:  16,
              fontStyle: FontStyle.italic,
              color:     const Color(0xFF3A2010),
              height:    1.55,
            ),
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Text(
            MemoryService.relativeTime(memory.createdAt),
            style: GoogleFonts.fraunces(
              fontSize: 12,
              color:    const Color(0xFF9B7A5A),
            ),
          ),
          const SizedBox(height: 14),
          const _ViewWallButton(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Photo memory card — image at its native aspect ratio (capped)
// ─────────────────────────────────────────────────────────────────────────────

class _PhotoMemoryCard extends StatelessWidget {
  final Memory  memory;
  final String? position;

  const _PhotoMemoryCard({super.key, required this.memory, this.position});

  @override
  Widget build(BuildContext context) {
    final file = File(memory.imagePath!);
    return Container(
      decoration: _cardDecoration,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _CardHeader(position: position),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: 280,   // adapt-to-content, but never balloons.
                minHeight: 140,
              ),
              child: Image.file(
                file,
                fit:   BoxFit.cover,
                width: double.infinity,
                errorBuilder: (_, __, ___) => Container(
                  height: 160,
                  color:  const Color(0xFFE8D5A3),
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_outlined,
                      color: Color(0xFF7A4E2A)),
                ),
              ),
            ),
          ),
          if (memory.text.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              memory.text,
              style: GoogleFonts.fraunces(
                fontSize:  14,
                fontStyle: FontStyle.italic,
                color:     const Color(0xFF3A2010),
                height:    1.5,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 10),
          Text(
            MemoryService.relativeTime(memory.createdAt),
            style: GoogleFonts.fraunces(
              fontSize: 12,
              color:    const Color(0xFF9B7A5A),
            ),
          ),
          const SizedBox(height: 12),
          const _ViewWallButton(),
        ],
      ),
    );
  }
}

// ─── Shared bits ─────────────────────────────────────────────────────────────

final BoxDecoration _cardDecoration = BoxDecoration(
  gradient: const LinearGradient(
    begin:  Alignment.topLeft,
    end:    Alignment.bottomRight,
    colors: [Color(0xFFFBF0D8), Color(0xFFF4E3C0)],
  ),
  borderRadius: BorderRadius.circular(22),
  border:       Border.all(color: const Color(0xFFD4B896), width: 1.5),
  boxShadow:    const [
    BoxShadow(color: Color(0x18000000), blurRadius: 16, offset: Offset(0, 5)),
  ],
);

class _CardHeader extends StatelessWidget {
  final String? position;
  const _CardHeader({this.position});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color:        const Color(0xFFE8D5A3),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.menu_book_rounded,
              color: Color(0xFF7A4E2A), size: 16),
        ),
        const SizedBox(width: 10),
        Text(
          'Memory Wall',
          style: GoogleFonts.fraunces(
            fontSize:   18,
            fontWeight: FontWeight.w600,
            color:      const Color(0xFF3A2010),
          ),
        ),
        const Spacer(),
        if (position != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color:        const Color(0xFFE8D5A3),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              position!,
              style: GoogleFonts.fraunces(
                fontSize: 11,
                color:    const Color(0xFF7A4E2A),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}

class _SubLabel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'A note from past you',
          style: GoogleFonts.fraunces(
            fontSize:   13,
            fontWeight: FontWeight.w500,
            color:      const Color(0xFF7A5A3A),
          ),
        ),
        const SizedBox(width: 6),
        const Icon(Icons.favorite, color: Color(0xFFD4A853), size: 13),
      ],
    );
  }
}

class _ViewWallButton extends StatelessWidget {
  const _ViewWallButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color:        const Color(0xFF5C3220),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'View Memory Wall',
            style: GoogleFonts.fraunces(
              fontSize:   13,
              fontWeight: FontWeight.w600,
              color:      Colors.white,
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.arrow_forward, color: Colors.white, size: 14),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyMemoryCard extends StatelessWidget {
  final EdgeInsets margin;
  const _EmptyMemoryCard({required this.margin});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MemoryWallScreen()),
        ),
        child: Container(
          decoration: _cardDecoration,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CardHeader(),
              const SizedBox(height: 14),
              Text(
                'Save notes or photos that remind you how far you\'ve come.\nThey\'ll show up here — just for you.',
                style: GoogleFonts.fraunces(
                  fontSize: 14,
                  color:    const Color(0xFF7A5A3A),
                  height:   1.55,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color:        const Color(0xFF5C3220),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Add your first memory',
                      style: GoogleFonts.fraunces(
                        fontSize:   13,
                        fontWeight: FontWeight.w600,
                        color:      Colors.white,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_forward, color: Colors.white, size: 14),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
