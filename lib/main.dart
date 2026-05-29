import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'core/notifications/notification_service.dart';
import 'core/theme/app_theme.dart';
import 'shell/home_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await NotificationService.init();
  // Request SMS permissions before the app renders so the BroadcastReceiver
  // can fire on the very first SMS — don't wait for the user to open the
  // inbox tab and notice the banner.
  await Permission.sms.request();
  runApp(const ProviderScope(child: DefendraApp()));
}

class DefendraApp extends StatelessWidget {
  const DefendraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Defendra',
      debugShowCheckedModeBanner: false,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: const HomeShell(),
    );
  }
}
