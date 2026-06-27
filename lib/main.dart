import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'screens/welcome_screen.dart';
import 'services/identity_service.dart';
import 'services/notification_service.dart';
import 'services/warmup_service.dart';
import 'widgets/chat_ready_banner.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // Anonymous UUID exists from the very first launch (fire & forget).
  IdentityService().getUserId();

  // Notifications: init + read cold-start payload + re-arm persistent
  // panic-room shortcut if the user previously had it enabled.
  await NotificationService().initialize();
  await NotificationService().loadColdStartPayload();
  if (await NotificationService().isPanicShortcutEnabled()) {
    // Re-show on every cold start so the tray entry survives reboots.
    unawaited(NotificationService().showPanicShortcut());
  }

  // Ping Railway /health so the cold-start dyno wakes up in the background.
  WarmupService().warmUp();

  runApp(const WaywellApp());
}

// Tiny helper so we don't need to import dart:async just for `unawaited`.
void unawaited(Future<void> _) {}

class WaywellApp extends StatelessWidget {
  const WaywellApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Waywell',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const WelcomeScreen(),
      builder: (context, child) => ChatReadyBanner(child: child!),
    );
  }
}
