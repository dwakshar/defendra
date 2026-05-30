import 'package:flutter/material.dart';
import '../colors.dart';
import '../typography.dart';

class EmptyState extends StatelessWidget {
  final String label;
  final String? sublabel;

  const EmptyState({super.key, required this.label, this.sublabel});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _EmptyIllustration(color: context.dBorder),
          const SizedBox(height: 16),
          Text(label, style: context.dtMonoSmall),
          if (sublabel != null) ...[
            const SizedBox(height: 4),
            Text(
              sublabel!,
              style: context.dtMonoSmall.copyWith(
                color: context.dBorder,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyIllustration extends StatelessWidget {
  final Color color;
  const _EmptyIllustration({required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(44, 28),
      painter: _LinesPainter(color: color),
    );
  }
}

class _LinesPainter extends CustomPainter {
  final Color color;
  const _LinesPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(0, size.height * 0.15), Offset(size.width, size.height * 0.15), paint);
    canvas.drawLine(Offset(0, size.height * 0.50), Offset(size.width * 0.62, size.height * 0.50), paint);
    canvas.drawLine(Offset(0, size.height * 0.85), Offset(size.width * 0.35, size.height * 0.85), paint);
  }

  @override
  bool shouldRepaint(_LinesPainter old) => old.color != color;
}
