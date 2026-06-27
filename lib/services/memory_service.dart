import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A single saved memory. Either a written note ([text]) or a photo
/// ([imagePath] points to a file in the app's documents dir). Text and
/// photo can coexist — a photo may have an optional caption.
class Memory {
  final String   id;
  final String   text;
  final String?  imagePath;
  final DateTime createdAt;

  Memory({
    required this.id,
    required this.text,
    this.imagePath,
    required this.createdAt,
  });

  bool get isPhoto => imagePath != null && imagePath!.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'id':        id,
    'text':      text,
    if (imagePath != null) 'imagePath': imagePath,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Memory.fromJson(Map<String, dynamic> j) => Memory(
    id:        j['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
    text:      _sanitize(j['text']?.toString() ?? ''),
    imagePath: (j['imagePath'] as String?)?.trim().isEmpty == true
        ? null
        : j['imagePath'] as String?,
    createdAt: j['createdAt'] != null
        ? DateTime.tryParse(j['createdAt'].toString()) ?? DateTime.now()
        : DateTime.now(),
  );
}

/// Decode URL-encoded artifacts (e.g. "You%20showed%20up" → "You showed up")
/// that can sneak in when text is typed via `adb shell input text`.
/// Safe for normal text — leaves it untouched if no %XX patterns exist.
String _sanitize(String input) {
  if (!input.contains('%')) return input;
  try {
    return Uri.decodeFull(input);
  } catch (_) {
    // Malformed escape — strip the common ones manually.
    return input
        .replaceAll('%20', ' ')
        .replaceAll('%0A', '\n')
        .replaceAll('%21', '!')
        .replaceAll('%27', "'")
        .replaceAll('%22', '"');
  }
}

class MemoryService extends ChangeNotifier {
  static final MemoryService _instance = MemoryService._internal();
  factory MemoryService() => _instance;
  MemoryService._internal();

  static const String _key = 'memories';

  /// Returns all memories sorted newest-first.
  Future<List<Memory>> getMemories() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List;
      final memories = list
          .map((j) {
            try {
              if (j is String) {
                // Legacy format — plain string stored before this service existed.
                return Memory(
                  id:        j.hashCode.toString(),
                  text:      _sanitize(j),
                  createdAt: DateTime.now(),
                );
              }
              return Memory.fromJson(j as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<Memory>()
          .toList();
      memories.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return memories;
    } catch (_) {
      return [];
    }
  }

  /// Adds a written-note memory.
  Future<void> addMemory(String text) async {
    final trimmed = _sanitize(text.trim());
    if (trimmed.isEmpty) return;
    final memories = await getMemories();
    memories.insert(
      0,
      Memory(
        id:        DateTime.now().millisecondsSinceEpoch.toString(),
        text:      trimmed,
        createdAt: DateTime.now(),
      ),
    );
    await _save(memories);
    notifyListeners();
  }

  /// Adds a photo-note memory. [imagePath] is an absolute file path inside
  /// the app's documents directory; [caption] is optional.
  Future<void> addPhotoMemory(String imagePath, {String caption = ''}) async {
    final trimmedPath = imagePath.trim();
    if (trimmedPath.isEmpty) return;
    final memories = await getMemories();
    memories.insert(
      0,
      Memory(
        id:        DateTime.now().millisecondsSinceEpoch.toString(),
        text:      _sanitize(caption.trim()),
        imagePath: trimmedPath,
        createdAt: DateTime.now(),
      ),
    );
    await _save(memories);
    notifyListeners();
  }

  /// Deletes the memory with [id] and notifies listeners.
  Future<void> deleteMemory(String id) async {
    final memories = await getMemories();
    memories.removeWhere((m) => m.id == id);
    await _save(memories);
    notifyListeners();
  }

  /// Returns the most recent memory text (skipping photo-only memories
  /// with no caption), or null if none exist.
  Future<String?> getMostRecent() async {
    final list = await getMemories();
    for (final m in list) {
      if (m.text.trim().isNotEmpty) return m.text;
    }
    return null;
  }

  Future<void> _save(List<Memory> memories) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(memories.map((m) => m.toJson()).toList()),
    );
  }

  /// Human-friendly relative time string.
  static String relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays == 0) return 'today';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7)  return '${diff.inDays} days ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} weeks ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()} months ago';
    return '${(diff.inDays / 365).floor()} years ago';
  }
}
