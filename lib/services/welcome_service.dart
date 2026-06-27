import 'package:shared_preferences/shared_preferences.dart';

/// Manages the once-per-calendar-day welcome screen logic.
///
/// Rules:
///   - First ever launch  → show welcome (no key stored yet)
///   - First launch of a NEW day → show welcome (stored date ≠ today)
///   - Subsequent launches on the SAME day → skip welcome (stored date = today)
class WelcomeService {
  static const String _lastWelcomeDateKey = 'last_welcome_shown_date';

  /// Returns [true] when the welcome screen should be displayed.
  static Future<bool> shouldShowWelcome() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_lastWelcomeDateKey);
    return stored != _todayString();
  }

  /// Call this when the user taps "Get Started" on the welcome screen.
  /// Records today's date so the screen is skipped for the rest of the day.
  static Future<void> markWelcomeShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastWelcomeDateKey, _todayString());
  }

  /// Formats today's date as 'yyyy-mm-dd' (no external dependency needed).
  static String _todayString() {
    final now = DateTime.now();
    final yyyy = now.year.toString();
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd';
  }
}
