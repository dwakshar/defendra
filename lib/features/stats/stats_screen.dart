import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../core/theme/widgets/empty_state.dart';
import '../../core/theme/widgets/shimmer.dart';
import 'stats_aggregator.dart';
import 'stats_provider.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWeek = ref.watch(statsRangeProvider);
    final async = ref.watch(statsDataProvider);

    return Scaffold(
      backgroundColor: context.dCanvas,
      appBar: AppBar(title: const Text('STATS')),
      body: async.when(
        loading: () => const _StatsShimmer(),
        error: (e, _) => Center(
          child: Text('error: $e', style: context.dtMonoSmall),
        ),
        data: (data) => data.totalScanned == 0
            ? const EmptyState(
                label: '~ no data yet',
                sublabel: 'intercept some SMS to see statistics',
              )
            : _StatsBody(data: data, isWeek: isWeek),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shimmer skeleton for stats loading
// ---------------------------------------------------------------------------

class _StatsShimmer extends StatelessWidget {
  const _StatsShimmer();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
      children: [
        // Range toggle skeleton
        DefendraShimmer(
          width: double.infinity,
          height: 34,
          borderRadius: 6,
        ),
        const SizedBox(height: 28),
        // Headline cards
        Row(
          children: const [
            Expanded(child: StatsShimmerCard()),
            SizedBox(width: 16),
            Expanded(child: StatsShimmerCard()),
          ],
        ),
        const SizedBox(height: 28),
        // Section skeleton
        DefendraShimmerFill(height: 10),
        const SizedBox(height: 12),
        DefendraShimmerFill(height: 60),
        const SizedBox(height: 28),
        DefendraShimmerFill(height: 10),
        const SizedBox(height: 12),
        DefendraShimmerFill(height: 100, borderRadius: 4),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Main body
// ---------------------------------------------------------------------------

class _StatsBody extends ConsumerWidget {
  const _StatsBody({required this.data, required this.isWeek});
  final StatsData data;
  final bool isWeek;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
      children: [
        _RangeToggle(isWeek: isWeek),
        const SizedBox(height: 28),
        _HeadlineRow(data: data),
        const SizedBox(height: 28),
        _VerdictDistribution(data: data),
        const SizedBox(height: 28),
        _ScamsOverTime(data: data, isWeek: isWeek),
        const SizedBox(height: 28),
        _CategoryBreakdown(data: data),
        const SizedBox(height: 28),
        _BottomCards(data: data),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Range toggle
// ---------------------------------------------------------------------------

class _RangeToggle extends ConsumerWidget {
  const _RangeToggle({required this.isWeek});
  final bool isWeek;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: context.dSurface,
        border: Border.all(color: context.dBorder, width: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          _Segment(
            label: '7D',
            selected: isWeek,
            onTap: () => ref.read(statsRangeProvider.notifier).state = true,
            leftRadius: true,
          ),
          _Segment(
            label: '30D',
            selected: !isWeek,
            onTap: () => ref.read(statsRangeProvider.notifier).state = false,
            leftRadius: false,
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.leftRadius,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool leftRadius;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: selected ? context.dCard : Colors.transparent,
            borderRadius: BorderRadius.only(
              topLeft: leftRadius ? const Radius.circular(5) : Radius.zero,
              bottomLeft: leftRadius ? const Radius.circular(5) : Radius.zero,
              topRight: !leftRadius ? const Radius.circular(5) : Radius.zero,
              bottomRight: !leftRadius ? const Radius.circular(5) : Radius.zero,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: context.dtMonoSmall.copyWith(
              color: selected ? context.dText : context.dMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Headline metrics
// ---------------------------------------------------------------------------

class _HeadlineRow extends StatelessWidget {
  const _HeadlineRow({required this.data});
  final StatsData data;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _BigStat(
            value: '${data.totalScanned}',
            label: 'SMS SCANNED',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _BigStat(
            value: '${data.scamsBlocked}',
            label: 'SCAMS BLOCKED',
            valueColor:
                data.scamsBlocked > 0 ? DefendraColors.scam : null,
          ),
        ),
      ],
    );
  }
}

class _BigStat extends StatelessWidget {
  const _BigStat({required this.value, required this.label, this.valueColor});
  final String value;
  final String label;
  final Color? valueColor;

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
          Text(
            value,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 36,
              fontWeight: FontWeight.w500,
              color: valueColor ?? context.dText,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: context.dtMonoSmall),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Verdict distribution
// ---------------------------------------------------------------------------

class _VerdictDistribution extends StatelessWidget {
  const _VerdictDistribution({required this.data});
  final StatsData data;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'VERDICT DISTRIBUTION',
      child: Column(
        children: [
          _VerdictRow(dot: DefendraColors.safe, label: 'safe', count: data.safeCount),
          const SizedBox(height: 10),
          _VerdictRow(dot: DefendraColors.suspicious, label: 'suspicious', count: data.suspiciousCount),
          const SizedBox(height: 10),
          _VerdictRow(dot: DefendraColors.scam, label: 'scam', count: data.scamCount),
        ],
      ),
    );
  }
}

class _VerdictRow extends StatelessWidget {
  const _VerdictRow({required this.dot, required this.label, required this.count});
  final Color dot;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Text(label, style: context.dtMono),
        const Spacer(),
        Text(
          '$count',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: context.dText,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Scams over time chart
// ---------------------------------------------------------------------------

class _ScamsOverTime extends StatelessWidget {
  const _ScamsOverTime({required this.data, required this.isWeek});
  final StatsData data;
  final bool isWeek;

  @override
  Widget build(BuildContext context) {
    final buckets = data.scamsOverTime;
    final hasData = buckets.any((b) => b.scamCount > 0);

    return _Section(
      title: 'SCAMS OVER TIME',
      child: SizedBox(
        height: 120,
        child: hasData
            ? _LineChart(buckets: buckets, isWeek: isWeek)
            : Center(
                child: Text('no scams detected', style: context.dtMonoSmall),
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Line chart — custom painter.
// Straight segments (no bezier — bezier dips below 0 on sparse integer data).
// Gradient fill below the line, dots on non-zero days, today ring marker,
// faint ceiling guide at max, JetBrains Mono x-axis labels.
// ---------------------------------------------------------------------------

class _LineChart extends StatelessWidget {
  const _LineChart({required this.buckets, required this.isWeek});
  final List<DailyBucket> buckets;
  final bool isWeek;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LinePainter(
        buckets: buckets,
        isWeek: isWeek,
        accentColor: DefendraColors.scam,
        guideColor: context.dBorder,
        labelStyle: GoogleFonts.jetBrainsMono(
          fontSize: isWeek ? 10.0 : 9.0,
          color: context.dMuted,
          fontWeight: FontWeight.w400,
        ),
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.buckets,
    required this.isWeek,
    required this.accentColor,
    required this.guideColor,
    required this.labelStyle,
  });

  final List<DailyBucket> buckets;
  final bool isWeek;
  final Color accentColor;
  final Color guideColor;
  final TextStyle labelStyle;

  static const _kLabelH = 20.0;
  static const _kTopPad  = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    final n = buckets.length;
    if (n == 0) return;

    final maxCount = buckets.fold(0, (m, b) => b.scamCount > m ? b.scamCount : m);
    if (maxCount == 0) return;

    final chartH  = size.height - _kLabelH - _kTopPad;
    final baselineY = _kTopPad + chartH;

    // Map each bucket to a canvas point.
    Offset pt(int i) {
      final x = n == 1 ? size.width / 2 : i * size.width / (n - 1);
      final y = baselineY - (buckets[i].scamCount / maxCount) * chartH;
      return Offset(x, y);
    }

    final pts = List.generate(n, pt);

    // ── faint dashed ceiling guide at y = max ──────────────────────────────
    final dashPaint = Paint()
      ..color = guideColor
      ..strokeWidth = 0.5;
    const dashLen = 4.0;
    const gapLen  = 4.0;
    double dx = 0;
    while (dx < size.width) {
      canvas.drawLine(
        Offset(dx, _kTopPad),
        Offset((dx + dashLen).clamp(0, size.width), _kTopPad),
        dashPaint,
      );
      dx += dashLen + gapLen;
    }

    // ── baseline rule ──────────────────────────────────────────────────────
    canvas.drawLine(
      Offset(0, baselineY),
      Offset(size.width, baselineY),
      Paint()..color = guideColor..strokeWidth = 0.5,
    );

    // ── gradient fill below the line ──────────────────────────────────────
    final fillPath = Path()..moveTo(pts.first.dx, baselineY);
    for (final p in pts) { fillPath.lineTo(p.dx, p.dy); }
    fillPath
      ..lineTo(pts.last.dx, baselineY)
      ..close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accentColor.withValues(alpha: 0.18),
            accentColor.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, _kTopPad, size.width, chartH)),
    );

    // ── line ──────────────────────────────────────────────────────────────
    final linePath = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < n; i++) { linePath.lineTo(pts[i].dx, pts[i].dy); }

    canvas.drawPath(
      linePath,
      Paint()
        ..color = accentColor
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // ── dots on non-zero days ─────────────────────────────────────────────
    for (int i = 0; i < n; i++) {
      if (buckets[i].scamCount == 0) continue;
      final isToday = i == n - 1;

      if (isToday) {
        // Outer ring
        canvas.drawCircle(
          pts[i],
          5.5,
          Paint()
            ..color = accentColor.withValues(alpha: 0.25)
            ..style = PaintingStyle.fill,
        );
        canvas.drawCircle(
          pts[i],
          5.5,
          Paint()
            ..color = accentColor
            ..strokeWidth = 1.0
            ..style = PaintingStyle.stroke,
        );
      }

      // Filled dot
      canvas.drawCircle(
        pts[i],
        isToday ? 3.0 : 2.5,
        Paint()..color = accentColor,
      );
    }

    // ── x-axis labels ─────────────────────────────────────────────────────
    for (int i = 0; i < n; i++) {
      final label = _label(i, n);
      if (label == null) continue;

      final tp = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: 32);

      tp.paint(
        canvas,
        Offset(pts[i].dx - tp.width / 2, size.height - _kLabelH + 4),
      );
    }
  }

  String? _label(int i, int n) {
    if (isWeek) {
      const abbr = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
      return abbr[(buckets[i].date.weekday - 1) % 7];
    }
    // 30 D: first, every 7th, last
    if (i == 0 || i % 7 == 0 || i == n - 1) {
      return '${buckets[i].date.day}';
    }
    return null;
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      !identical(old.buckets, buckets) || old.isWeek != isWeek;
}

// ---------------------------------------------------------------------------
// Category breakdown
// ---------------------------------------------------------------------------

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({required this.data});
  final StatsData data;

  static const _order = ['otp', 'kyc', 'delivery', 'job', 'lottery', 'other'];

  @override
  Widget build(BuildContext context) {
    final cats = data.categoryBreakdown;
    final maxVal =
        _order.map((k) => cats[k] ?? 0).fold(0, (a, b) => a > b ? a : b);

    return _Section(
      title: 'CATEGORY BREAKDOWN',
      child: Column(
        children: [
          for (int i = 0; i < _order.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _CategoryRow(
              label: _order[i],
              count: cats[_order[i]] ?? 0,
              maxCount: maxVal,
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.label,
    required this.count,
    required this.maxCount,
  });
  final String label;
  final int count;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final frac = maxCount == 0 ? 0.0 : count / maxCount;

    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(label, style: context.dtMonoSmall),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: LayoutBuilder(builder: (ctx, box) {
            return Stack(
              children: [
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: context.dSurface,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOut,
                  height: 3,
                  width: box.maxWidth * frac,
                  decoration: BoxDecoration(
                    color: context.dMuted,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            );
          }),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 28,
          child: Text(
            '$count',
            textAlign: TextAlign.right,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: context.dMuted,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom stat cards
// ---------------------------------------------------------------------------

class _BottomCards extends StatelessWidget {
  const _BottomCards({required this.data});
  final StatsData data;

  @override
  Widget build(BuildContext context) {
    final saved = data.estimatedMoneySaved;
    final savStr = saved >= 1000
        ? '₹${(saved / 1000).toStringAsFixed(0)}K'
        : '₹${saved.toStringAsFixed(0)}';

    return Row(
      children: [
        Expanded(child: _StatCard(value: savStr, label: 'EST. SAVED')),
        const SizedBox(width: 16),
        Expanded(child: _StatCard(value: '${data.streak}d', label: 'STREAK')),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label});
  final String value;
  final String label;

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
          Text(
            value,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 28,
              fontWeight: FontWeight.w500,
              color: context.dText,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: context.dtMonoSmall),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section wrapper
// ---------------------------------------------------------------------------

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.dtMonoSmall),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}
