import 'package:fl_chart/fl_chart.dart';
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
        height: 100,
        child: hasData
            ? _LineChart(buckets: buckets, isWeek: isWeek)
            : Center(
                child: Text('no scams detected', style: context.dtMonoSmall),
              ),
      ),
    );
  }
}

class _LineChart extends StatelessWidget {
  const _LineChart({required this.buckets, required this.isWeek});
  final List<DailyBucket> buckets;
  final bool isWeek;

  @override
  Widget build(BuildContext context) {
    final maxY = buckets
        .map((b) => b.scamCount)
        .fold(0, (a, b) => a > b ? a : b)
        .toDouble();

    final spots = buckets.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.scamCount.toDouble());
    }).toList();

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (buckets.length - 1).toDouble(),
        minY: 0,
        maxY: maxY < 1 ? 1 : maxY + 0.5,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: isWeek ? 1 : 6,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= buckets.length) return const SizedBox();
                final d = buckets[idx].date;
                final label = isWeek ? _weekDay(d.weekday) : '${d.day}';
                return Text(
                  label,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    color: context.dMuted,
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.3,
            color: DefendraColors.scam,
            barWidth: 1.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: DefendraColors.scam.withValues(alpha: 0.06),
            ),
          ),
        ],
      ),
    );
  }

  static String _weekDay(int d) {
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return days[(d - 1) % 7];
  }
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
