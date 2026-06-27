import 'dart:async';
import 'package:flutter/foundation.dart';

// Auto bright/dark theme based on local time.
//   • 06:00–19:59 → bright
//   • 20:00–05:59 → dark
//
// The notifier ticks once a minute so the home screen flips at the boundary
// without a restart.
class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal() {
    _start();
  }

  Timer? _timer;
  bool _isDark = _computeDark();

  bool get isDark => _isDark;

  static bool _computeDark() {
    final h = DateTime.now().hour;
    return h >= 20 || h < 6;
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      final next = _computeDark();
      if (next != _isDark) {
        _isDark = next;
        notifyListeners();
      }
    });
  }

  // Call this on resume from background to re-evaluate immediately.
  void refresh() {
    final next = _computeDark();
    if (next != _isDark) {
      _isDark = next;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
