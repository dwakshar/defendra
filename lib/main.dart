import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/notifications/notification_service.dart';
import 'core/theme/app_theme.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/settings/settings_provider.dart';
import 'features/splash/splash_screen.dart';
import 'shell/home_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await NotificationService.init();

  final settings = await Hive.openBox('settings');
  final seenOnboarding =
      settings.get('seen_onboarding', defaultValue: false) as bool;

  runApp(ProviderScope(child: DefendraApp(showOnboarding: !seenOnboarding)));
}

class DefendraApp extends ConsumerWidget {
  const DefendraApp({super.key, required this.showOnboarding});

  final bool showOnboarding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lightMode = ref.watch(lightModeProvider);
    return MaterialApp(
      title: 'Defendra',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: lightMode ? ThemeMode.light : ThemeMode.dark,
      home: SplashScreen(
        next: showOnboarding ? const OnboardingScreen() : const HomeShell(),
      ),
    );
  }
}
