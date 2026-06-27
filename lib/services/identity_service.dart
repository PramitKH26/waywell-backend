import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Generates a stable, device-bound anonymous ID.
///
/// On Android: uses ANDROID_ID (survives app reinstall, unique per device+user).
/// On iOS: uses identifierForVendor (resets only on full OS reinstall).
/// Fallback: random UUID v4 persisted in SharedPreferences.
class IdentityService {
  static final IdentityService _instance = IdentityService._internal();
  factory IdentityService() => _instance;
  IdentityService._internal();

  static const String _idKey = 'anonymous_user_id_v2';
  String? _cachedId;

  Future<String> getUserId() async {
    if (_cachedId != null) return _cachedId!;

    final prefs = await SharedPreferences.getInstance();

    // Return stored ID if we already have one
    final stored = prefs.getString(_idKey);
    if (stored != null && stored.isNotEmpty) {
      _cachedId = stored;
      return _cachedId!;
    }

    // Try to get a hardware-bound device identifier
    String? deviceId;
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        // ANDROID_ID: unique per device + Google account, stable across reinstalls
        final aid = android.id;
        if (aid.isNotEmpty && aid != 'unknown') deviceId = 'and_$aid';
      } else if (Platform.isIOS) {
        final ios = await info.iosInfo;
        final idfv = ios.identifierForVendor;
        if (idfv != null && idfv.isNotEmpty) deviceId = 'ios_$idfv';
      }
    } catch (_) {}

    // Fall back to random UUID if device ID unavailable
    final id = deviceId ?? 'uuid_${const Uuid().v4()}';
    await prefs.setString(_idKey, id);
    _cachedId = id;
    return _cachedId!;
  }
}
