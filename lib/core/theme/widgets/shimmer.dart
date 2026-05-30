import 'package:flutter/material.dart';
import '../colors.dart';

/// A single skeleton shimmer block. Use LayoutBuilder for fill-width cases.
class DefendraShimmer extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const DefendraShimmer({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 3,
  });

  @override
  State<DefendraShimmer> createState() => _DefendraShimmerState();
}

class _DefendraShimmerState extends State<DefendraShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
    _anim = Tween<double>(begin: -1.5, end: 1.5).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = context.dCard;
    final shine = context.isDark
        ? const Color(0xFF2E2E2E)
        : const Color(0xFFE0E0E0);

    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          gradient: LinearGradient(
            begin: Alignment(_anim.value - 1, 0),
            end: Alignment(_anim.value + 1, 0),
            colors: [base, shine, base],
          ),
        ),
      ),
    );
  }
}

/// A full-width shimmer — fills available horizontal space via LayoutBuilder.
class DefendraShimmerFill extends StatelessWidget {
  final double height;
  final double borderRadius;

  const DefendraShimmerFill({
    super.key,
    required this.height,
    this.borderRadius = 3,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => DefendraShimmer(
        width: constraints.maxWidth,
        height: height,
        borderRadius: borderRadius,
      ),
    );
  }
}

/// A shimmer skeleton shaped like an inbox scan card row.
class InboxShimmerCard extends StatelessWidget {
  const InboxShimmerCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.dCard,
        border: Border.all(color: context.dBorder, width: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DefendraShimmer(width: 6, height: 6, borderRadius: 3),
              const SizedBox(width: 10),
              DefendraShimmer(width: 72, height: 11),
              const Spacer(),
              DefendraShimmer(width: 36, height: 10),
            ],
          ),
          const SizedBox(height: 8),
          DefendraShimmerFill(height: 10),
        ],
      ),
    );
  }
}

/// Shimmer skeleton shaped like a stats headline card.
class StatsShimmerCard extends StatelessWidget {
  const StatsShimmerCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: context.dCard,
        border: Border.all(color: context.dBorder, width: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefendraShimmer(width: 56, height: 32),
          const SizedBox(height: 8),
          DefendraShimmer(width: 80, height: 10),
        ],
      ),
    );
  }
}
