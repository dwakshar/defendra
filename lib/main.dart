import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/theme/app_theme.dart';
import 'shell/home_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter(); // boxes opened in Phase 2
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
