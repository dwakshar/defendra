import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/colors.dart';
import '../features/scanner/scanner_screen.dart';
import '../features/inbox/inbox_screen.dart';
import '../features/stats/stats_screen.dart';
import '../features/settings/settings_screen.dart';

final _tabIndexProvider = StateProvider<int>((ref) => 0);

const _screens = [
  ScannerScreen(),
  InboxScreen(),
  StatsScreen(),
  SettingsScreen(),
];

const _navItems = [
  BottomNavigationBarItem(icon: Icon(Icons.terminal_outlined), label: 'Scan'),
  BottomNavigationBarItem(icon: Icon(Icons.inbox_outlined), label: 'Inbox'),
  BottomNavigationBarItem(icon: Icon(Icons.bar_chart_outlined), label: 'Stats'),
  BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: 'Settings'),
];

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(_tabIndexProvider);

    return Scaffold(
      backgroundColor: context.dCanvas,
      body: IndexedStack(
        index: currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: context.dBorder, width: 0.5),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: (i) => ref.read(_tabIndexProvider.notifier).state = i,
          items: _navItems,
        ),
      ),
    );
  }
}
