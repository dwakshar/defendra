import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/widgets/empty_state.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DefendraColors.canvas,
      appBar: AppBar(
        title: const Text('SETTINGS'),
      ),
      body: const EmptyState(label: '// not implemented'),
    );
  }
}
