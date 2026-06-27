import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WarmupService — fire-and-forget Railway health ping at app launch.
//
// Purpose: Railway's free tier sleeps after inactivity.  A cold start can
// take 30-60 s.  By pinging /health the moment main() runs, the dyno is
// awake before the user even reaches the chat screen.
//
// Uses a short 10 s timeout — if the ping itself fails (no internet, etc.)
// we silently move on.  The first real /chat request uses 90 s timeout as
// an extra safety net.
// ─────────────────────────────────────────────────────────────────────────────

class WarmupService {
  static final WarmupService _instance = WarmupService._internal();
  factory WarmupService() => _instance;
  WarmupService._internal();

  bool _hasWarmedUp = false;

  Future<void> warmUp() async {
    if (_hasWarmedUp) return;
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.healthEndpoint}');
      await http.get(uri).timeout(const Duration(seconds: 10));
      _hasWarmedUp = true;
      debugPrint('[WARMUP] Backend is warm ✓');
    } catch (e) {
      // Fail silently — never block the user.
      // The first /chat request will wake the dyno if this ping fails.
      debugPrint('[WARMUP] Ping failed (will retry on first message): $e');
    }
  }
}
