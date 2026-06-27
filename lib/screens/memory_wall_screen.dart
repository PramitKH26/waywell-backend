import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../services/memory_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MemoryWallScreen
// Empty: shows two example note cards.
// Populated: real memories newest-first, scattered with rotation. Long-press
// to delete. Supports written notes AND photo notes (image_picker).
// ─────────────────────────────────────────────────────────────────────────────

class MemoryWallScreen extends StatefulWidget {
  const MemoryWallScreen({super.key});

  static const _bg       = Color(0xFFF5E6C0);
  static const _ink      = Color(0xFF3D2817);
  static const _accent   = Color(0xFF8B6030);
  static const _btnBrown = Color(0xFF6B3A2A);
  static const _muted    = Color(0xFFB0957A);
  static const _panelBg  = Color(0xFFFAF0DC);

  @override
  State<MemoryWallScreen> createState() => _MemoryWallScreenState();
}

class _MemoryWallScreenState extends State<MemoryWallScreen> {
  List<Memory> _memories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    MemoryService().addListener(_reload);
    _loadMemories();
  }

  @override
  void dispose() {
    MemoryService().removeListener(_reload);
    super.dispose();
  }

  void _reload() => _loadMemories();

  Future<void> _loadMemories() async {
    final list = await MemoryService().getMemories();
    if (!mounted) return;
    setState(() {
      _memories = list;
      _loading  = false;
    });
  }

  Future<void> _openMemory(Memory m, Color color) async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.65),
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) => _MemoryDetailScreen(memory: m, color: color),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  Future<void> _deleteMemory(Memory m) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: MemoryWallScreen._panelBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Remove this memory?',
            style: GoogleFonts.fraunces(
                fontSize: 18, color: MemoryWallScreen._ink)),
        content: Text(
          m.isPhoto
              ? 'This photo memory will be removed.'
              : (m.text.length > 80 ? '${m.text.substring(0, 80)}…' : m.text),
          style: GoogleFonts.fraunces(
              fontSize: 14, color: MemoryWallScreen._muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Keep',
                style: GoogleFonts.fraunces(color: MemoryWallScreen._accent)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Remove',
                style: GoogleFonts.fraunces(color: MemoryWallScreen._btnBrown,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      // Best-effort cleanup of the underlying file.
      if (m.isPhoto) {
        try { await File(m.imagePath!).delete(); } catch (_) {}
      }
      await MemoryService().deleteMemory(m.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MemoryWallScreen._bg,
      body: SafeArea(
        child: Column(
          children: [
            const _Header(),
            const SizedBox(height: 4),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: MemoryWallScreen._accent))
                  : _buildWall(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWall() {
    final hasReal = _memories.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!hasReal) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 12),
              child: Text(
                'Examples — add your own ↓',
                style: GoogleFonts.fraunces(
                    fontSize: 13, color: MemoryWallScreen._muted),
              ),
            ),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: List.generate(_kExamples.length, (i) {
                final angle = _kAngles[i % _kAngles.length];
                return Transform.rotate(
                  angle: angle,
                  child: _NoteCard(
                    text:  _kExamples[i],
                    color: _kCardColors[i % _kCardColors.length],
                  ),
                );
              }),
            ),
          ] else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: List.generate(_memories.length, (i) {
                final m     = _memories[i];
                final angle = _kAngles[i % _kAngles.length];
                final color = _kCardColors[i % _kCardColors.length];
                return Transform.rotate(
                  angle: angle,
                  child: GestureDetector(
                    onTap: () => _openMemory(m, color),
                    onLongPress: () => _deleteMemory(m),
                    child: m.isPhoto
                        ? _PhotoNoteCard(memory: m, color: color)
                        : _NoteCard(
                            text:  m.text,
                            date:  MemoryService.relativeTime(m.createdAt),
                            color: color,
                          ),
                  ),
                );
              }),
            ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () => _showAddMemorySheet(context, _reload),
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color:        MemoryWallScreen._btnBrown,
                borderRadius: BorderRadius.circular(26),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Add a memory',
                    style: GoogleFonts.fraunces(
                      fontSize:   15,
                      fontWeight: FontWeight.w500,
                      color:      Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (hasReal)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Center(
                child: Text(
                  'Long-press a card to remove it',
                  style: GoogleFonts.fraunces(
                      fontSize: 12, color: MemoryWallScreen._muted),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Constants ───────────────────────────────────────────────────────────────

const _kAngles = [-0.03, 0.025, -0.015, 0.04, -0.02, 0.03];

const _kCardColors = [
  Color(0xFFFFF3C4),
  Color(0xFFD4EED4),
  Color(0xFFFFDEDE),
  Color(0xFFD4E8FF),
  Color(0xFFFFE8CC),
];

const _kExamples = [
  'Submitted my final year project on time 🎉',
  'Called home even when I was overwhelmed — it helped.',
];

// ─── Memory detail viewer ────────────────────────────────────────────────────

class _MemoryDetailScreen extends StatelessWidget {
  final Memory memory;
  final Color  color;
  const _MemoryDetailScreen({required this.memory, required this.color});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          behavior: HitTestBehavior.opaque,
          child: Center(
            child: GestureDetector(
              onTap: () {}, // absorb taps on the card itself
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color:        color,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(
                      color:      Color(0x44000000),
                      blurRadius: 24,
                      offset:     Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (memory.isPhoto) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(memory.imagePath!),
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Container(
                            height: 200,
                            color: MemoryWallScreen._panelBg,
                            alignment: Alignment.center,
                            child: const Icon(Icons.broken_image_outlined,
                                color: MemoryWallScreen._muted, size: 40),
                          ),
                        ),
                      ),
                      if (memory.text.isNotEmpty) const SizedBox(height: 16),
                    ],
                    if (memory.text.isNotEmpty)
                      Text(
                        memory.text,
                        style: GoogleFonts.fraunces(
                          fontSize: 17,
                          height:   1.55,
                          color:    MemoryWallScreen._ink,
                        ),
                      ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          MemoryService.relativeTime(memory.createdAt),
                          style: GoogleFonts.fraunces(
                            fontSize: 12,
                            color:    MemoryWallScreen._muted,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color:        MemoryWallScreen._btnBrown,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Close',
                              style: GoogleFonts.fraunces(
                                fontSize:   13,
                                color:      Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Text note card ──────────────────────────────────────────────────────────

class _NoteCard extends StatelessWidget {
  final String  text;
  final String? date;
  final Color   color;

  const _NoteCard({required this.text, required this.color, this.date});

  @override
  Widget build(BuildContext context) {
    final w = (MediaQuery.of(context).size.width - 44) / 2;
    return Container(
      width:   w,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        color,
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [
          BoxShadow(
            color:      Color(0x22000000),
            blurRadius: 8,
            offset:     Offset(2, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: GoogleFonts.fraunces(
              fontSize: 13,
              color:    MemoryWallScreen._ink,
              height:   1.5,
            ),
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
          ),
          if (date != null) ...[
            const SizedBox(height: 8),
            Text(
              date!,
              style: GoogleFonts.fraunces(
                fontSize: 11,
                color:    MemoryWallScreen._muted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Photo note card ─────────────────────────────────────────────────────────

class _PhotoNoteCard extends StatelessWidget {
  final Memory memory;
  final Color  color;

  const _PhotoNoteCard({required this.memory, required this.color});

  @override
  Widget build(BuildContext context) {
    final w = (MediaQuery.of(context).size.width - 44) / 2;
    return Container(
      width:   w,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color:        color,
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [
          BoxShadow(
            color:      Color(0x22000000),
            blurRadius: 8,
            offset:     Offset(2, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Image.file(
              File(memory.imagePath!),
              width:  double.infinity,
              fit:    BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 120,
                color:  MemoryWallScreen._panelBg,
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image_outlined,
                    color: MemoryWallScreen._muted),
              ),
            ),
          ),
          if (memory.text.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                memory.text,
                style: GoogleFonts.fraunces(
                  fontSize: 12,
                  color:    MemoryWallScreen._ink,
                  height:   1.45,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              MemoryService.relativeTime(memory.createdAt),
              style: GoogleFonts.fraunces(
                fontSize: 11,
                color:    MemoryWallScreen._muted,
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ─── Header ──────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Stack(
        children: [
          Positioned(
            left: 8, top: 4,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new,
                  size: 20, color: MemoryWallScreen._ink),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          Center(
            child: Text(
              'Memory Wall',
              style: GoogleFonts.caveat(
                fontSize:   24,
                fontWeight: FontWeight.w600,
                color:      MemoryWallScreen._ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Add-memory bottom sheet ─────────────────────────────────────────────────

void _showAddMemorySheet(BuildContext context, VoidCallback onSaved) {
  showModalBottomSheet(
    context:          context,
    isScrollControlled: true,
    backgroundColor: MemoryWallScreen._bg,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _AddMemorySheet(onSaved: onSaved),
    ),
  );
}

class _AddMemorySheet extends StatelessWidget {
  final VoidCallback onSaved;
  const _AddMemorySheet({required this.onSaved});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color:        MemoryWallScreen._muted.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Add a memory',
            style: GoogleFonts.caveat(
              fontSize:   20,
              fontWeight: FontWeight.w600,
              color:      MemoryWallScreen._ink,
            ),
          ),
          const SizedBox(height: 16),
          _AddOption(
            icon:      Icons.edit_outlined,
            iconColor: MemoryWallScreen._accent,
            title:     'Write a note',
            subtitle:  'A moment, a win, a thought.',
            onTap: () {
              Navigator.of(context).pop();
              _showWriteNoteSheet(context, onSaved);
            },
          ),
          const SizedBox(height: 12),
          _AddOption(
            icon:      Icons.photo_library_outlined,
            iconColor: const Color(0xFF534AB7),
            title:     'Photo note from gallery',
            subtitle:  'A photo + a few words about it.',
            onTap: () async {
              final rootCtx = Navigator.of(context, rootNavigator: true).context;
              Navigator.of(context).pop();
              await _pickAndSavePhoto(rootCtx, ImageSource.gallery, onSaved);
            },
          ),
          const SizedBox(height: 12),
          _AddOption(
            icon:      Icons.camera_alt_outlined,
            iconColor: const Color(0xFF4A7C59),
            title:     'Take a photo note',
            subtitle:  'Capture this moment + a note.',
            onTap: () async {
              final rootCtx = Navigator.of(context, rootNavigator: true).context;
              Navigator.of(context).pop();
              await _pickAndSavePhoto(rootCtx, ImageSource.camera, onSaved);
            },
          ),
        ],
      ),
    );
  }
}

Future<void> _pickAndSavePhoto(
    BuildContext context, ImageSource source, VoidCallback onSaved) async {
  String? destPath;
  try {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source:       source,
      maxWidth:     2000,
      maxHeight:    2000,
      imageQuality: 85,
    );
    if (xfile == null) return;

    // Copy into the app's documents dir so it survives image_picker's
    // cache cleanup and the OS clearing temp storage.
    final docs = await getApplicationDocumentsDirectory();
    final memoriesDir = Directory('${docs.path}/memories');
    if (!memoriesDir.existsSync()) memoriesDir.createSync(recursive: true);
    final safeName = xfile.name.replaceAll(RegExp(r"[^a-zA-Z0-9_.-]"), "_");
    destPath = '${memoriesDir.path}/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    await File(xfile.path).copy(destPath);

    if (!context.mounted) {
      // Lost the UI context — still persist the photo so it isn't lost.
      await MemoryService().addPhotoMemory(destPath, caption: '');
      return;
    }

    // Combined "photo + note" sheet. Returns the entered caption, or null
    // if the user dismissed without confirming.
    final caption = await _showPhotoNoteSheet(context, destPath);

    if (caption == null) {
      // Dismissed without saving — keep the file, drop the entry.
      try { await File(destPath).delete(); } catch (_) {}
      return;
    }

    await MemoryService().addPhotoMemory(destPath, caption: caption);
    onSaved();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Photo memory saved',
            style: GoogleFonts.fraunces(color: Colors.white, fontSize: 14)),
        backgroundColor: MemoryWallScreen._btnBrown,
        behavior:        SnackBarBehavior.floating,
        margin:          const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  } catch (e) {
    // Best-effort cleanup of the orphan file.
    if (destPath != null) {
      try { await File(destPath).delete(); } catch (_) {}
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Couldn\'t save photo: $e',
            style: GoogleFonts.fraunces(color: Colors.white, fontSize: 13)),
        backgroundColor: const Color(0xFF8B4444),
        behavior:        SnackBarBehavior.floating,
        margin:          const EdgeInsets.all(16),
      ),
    );
  }
}

/// Combined photo + caption sheet. Shows the picked photo and a note field.
/// Returns the caption (possibly empty) when the user taps Save, or null
/// when they dismiss / tap Discard.
Future<String?> _showPhotoNoteSheet(BuildContext context, String imagePath) {
  return showModalBottomSheet<String?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: MemoryWallScreen._bg,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _PhotoNoteSheet(imagePath: imagePath),
    ),
  );
}

class _PhotoNoteSheet extends StatefulWidget {
  final String imagePath;
  const _PhotoNoteSheet({required this.imagePath});

  @override
  State<_PhotoNoteSheet> createState() => _PhotoNoteSheetState();
}

class _PhotoNoteSheetState extends State<_PhotoNoteSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: MemoryWallScreen._muted.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Photo note',
            style: GoogleFonts.caveat(
                fontSize: 22, fontWeight: FontWeight.w600,
                color: MemoryWallScreen._ink),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.file(
              File(widget.imagePath),
              height: 220,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 220,
                color: MemoryWallScreen._panelBg,
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image_outlined,
                    color: MemoryWallScreen._muted, size: 40),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 3,
            minLines: 2,
            style: GoogleFonts.fraunces(
                color: MemoryWallScreen._ink, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'A note for this photo — what does it mean to you?',
              hintStyle: GoogleFonts.fraunces(
                  color: MemoryWallScreen._muted, fontSize: 13),
              filled:     true,
              fillColor:  MemoryWallScreen._panelBg,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: MemoryWallScreen._muted)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: MemoryWallScreen._muted)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: MemoryWallScreen._accent, width: 1.5)),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(null),
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: MemoryWallScreen._panelBg,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                          color: MemoryWallScreen._muted, width: 0.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Discard',
                      style: GoogleFonts.fraunces(
                          fontSize: 14,
                          color: MemoryWallScreen._muted),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(_controller.text.trim()),
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                        color:        MemoryWallScreen._btnBrown,
                        borderRadius: BorderRadius.circular(24)),
                    alignment: Alignment.center,
                    child: Text(
                      'Save photo note',
                      style: GoogleFonts.fraunces(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddOption extends StatelessWidget {
  final IconData    icon;
  final Color       iconColor;
  final String      title;
  final String      subtitle;
  final VoidCallback onTap;

  const _AddOption({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:        MemoryWallScreen._panelBg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, size: 28, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.fraunces(
                          fontSize: 16, fontWeight: FontWeight.w500,
                          color: MemoryWallScreen._ink)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: GoogleFonts.fraunces(
                          fontSize: 13, color: MemoryWallScreen._muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Write-note sheet ─────────────────────────────────────────────────────────

void _showWriteNoteSheet(BuildContext context, VoidCallback onSaved) {
  showModalBottomSheet(
    context:          context,
    isScrollControlled: true,
    backgroundColor: MemoryWallScreen._bg,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) => FractionallySizedBox(
      heightFactor: 0.75,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _WriteNoteSheet(onSaved: onSaved),
      ),
    ),
  );
}

class _WriteNoteSheet extends StatefulWidget {
  final VoidCallback onSaved;
  const _WriteNoteSheet({required this.onSaved});

  @override
  State<_WriteNoteSheet> createState() => _WriteNoteSheetState();
}

class _WriteNoteSheetState extends State<_WriteNoteSheet> {
  final _controller = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await MemoryService().addMemory(text);
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.onSaved();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Memory saved 🤍',
            style: GoogleFonts.fraunces(color: Colors.white, fontSize: 14)),
        backgroundColor: MemoryWallScreen._btnBrown,
        behavior:        SnackBarBehavior.floating,
        margin:          const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color:        MemoryWallScreen._muted.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'What do you want to remember?',
            style: GoogleFonts.caveat(
                fontSize: 18, fontWeight: FontWeight.w600,
                color: MemoryWallScreen._ink),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TextField(
              controller: _controller,
              maxLines:   null,
              expands:    true,
              style: GoogleFonts.fraunces(
                  fontSize: 15, color: MemoryWallScreen._ink),
              decoration: InputDecoration(
                hintText: 'A small win. A good moment. Something that made today okay.',
                hintStyle: GoogleFonts.fraunces(
                    fontSize: 15, color: MemoryWallScreen._muted),
                filled:      true,
                fillColor:   MemoryWallScreen._panelBg,
                border:       OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: MemoryWallScreen._muted)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: MemoryWallScreen._muted)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: MemoryWallScreen._accent, width: 1.5)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _save,
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                  color:        MemoryWallScreen._btnBrown,
                  borderRadius: BorderRadius.circular(26)),
              alignment: Alignment.center,
              child: _saving
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation(Colors.white)))
                  : Text(
                      'Save this memory',
                      style: GoogleFonts.fraunces(
                          fontSize:   15,
                          fontWeight: FontWeight.w500,
                          color:      Colors.white),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
