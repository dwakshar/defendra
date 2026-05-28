import 'package:flutter/material.dart';
import '../colors.dart';
import '../typography.dart';

class EmptyState extends StatelessWidget {
  final String label;

  const EmptyState({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // status dot
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: DefendraColors.muted,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(height: 12),
          Text(label, style: DefendraType.monoSmall),
        ],
      ),
    );
  }
}
