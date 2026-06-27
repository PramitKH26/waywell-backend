import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// UserService — singleton ChangeNotifier that stores the user's first name.
//
// HomeScreen listens to this notifier so "Hi [Name]" updates the moment the
// user saves their name in MeScreen — no GlobalKey or tab-switch callbacks
// needed.
// ─────────────────────────────────────────────────────────────────────────────

class UserService extends ChangeNotifier {
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  static const String _nameKey         = 'user_name';
  static const String _seenNicknameKey = 'has_seen_nickname';

  // In-memory cache so repeated getName() calls don't hit disk each time.
  String? _cachedName;

  /// Returns the saved name, or null if not set.
  Future<String?> getName() async {
    if (_cachedName != null) return _cachedName;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_nameKey);
    _cachedName = (raw != null && raw.trim().isNotEmpty) ? raw.trim() : null;
    return _cachedName;
  }

  /// Saves [name] and notifies all listeners (e.g. HomeScreen).
  Future<void> setName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = name.trim();
    final toSave  = trimmed.length > 20 ? trimmed.substring(0, 20) : trimmed;
    if (toSave.isEmpty) {
      await prefs.remove(_nameKey);
      _cachedName = null;
    } else {
      await prefs.setString(_nameKey, toSave);
      _cachedName = toSave;
    }
    notifyListeners();
  }

  Future<bool> hasName() async {
    final n = await getName();
    return n != null && n.isNotEmpty;
  }

  /// Show the nickname screen only on the very first run with no name set.
  /// Once the user has either set a name or skipped it, never ask again.
  Future<bool> shouldShowNickname() async {
    final prefs = await SharedPreferences.getInstance();
    final seen  = prefs.getBool(_seenNicknameKey) ?? false;
    final named = await hasName();
    return !seen && !named;
  }

  Future<void> markNicknameSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_seenNicknameKey, true);
  }

  Future<void> clearName() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_nameKey);
    _cachedName = null;
    notifyListeners();
  }
}
