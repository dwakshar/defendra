import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../data/models/scan_record.dart';
import '../../ml/rule_matcher.dart';

class DetailScreen extends StatelessWidget {
  const DetailScreen({super.key, required this.record});

  final ScanRecord record;

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: 'scan_${record.id}',
      child: Material(
        color: DefendraColors.canvas,
        child: Scaffold(
          backgroundColor: DefendraColors.canvas,
          appBar: AppBar(
            backgroundColor: DefendraColors.canvas,
            elevation: 0,
            scrolledUnderElevation: 0,
            iconTheme: const IconThemeData(color: DefendraColors.muted),
            title: Text(
              record.sender,
              style: DefendraType.mono.copyWith(fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _VerdictCard(record: record),
              const SizedBox(height: 16),
              _BodyCard(record: record),
              if (record.triggeredRules.isNotEmpty) ...[
                const SizedBox(height: 16),
                _RulesCard(rules: record.triggeredRules),
              ],
              const SizedBox(height: 16),
              _MetadataFooter(record: record),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Verdict card
// ---------------------------------------------------------------------------

class _VerdictCard extends StatelessWidget {
  const _VerdictCard({required this.record});

  final ScanRecord record;

  Color get _accent => switch (record.verdict) {
        Verdict.safe => DefendraColors.safe,
        Verdict.suspicious => DefendraColors.suspicious,
        Verdict.scam => DefendraColors.scam,
      };

  String get _label => switch (record.verdict) {
        Verdict.safe => 'SAFE',
        Verdict.suspicious => 'SUSPICIOUS',
        Verdict.scam => 'SCAM',
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DefendraColors.card,
        border: Border.all(color: _accent, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: _accent,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${(record.confidence * 100).toStringAsFixed(1)}% confidence',
            style: DefendraType.monoSmall,
          ),
          const SizedBox(height: 2),
          Text(
            record.category,
            style: DefendraType.monoSmall,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body card — RichText with highlighted trigger phrases
// ---------------------------------------------------------------------------

class _BodyCard extends StatelessWidget {
  const _BodyCard({required this.record});

  final ScanRecord record;

  List<TextSpan> _buildSpans(String body) {
    final matches = RuleMatcher.allMatches(body);

    // Merge overlapping ranges
    final merged = <(int, int)>[];
    for (final m in matches) {
      if (merged.isEmpty || m.start >= merged.last.$2) {
        merged.add((m.start, m.end));
      } else if (m.end > merged.last.$2) {
        merged[merged.length - 1] = (merged.last.$1, m.end);
      }
    }

    final baseStyle = GoogleFonts.jetBrainsMono(
      fontSize: 13,
      color: DefendraColors.text,
      height: 1.6,
    );
    final highlightStyle = baseStyle.copyWith(
      decoration: TextDecoration.underline,
      decorationColor: DefendraColors.suspicious,
      decorationThickness: 1.5,
    );

    if (merged.isEmpty) return [TextSpan(text: body, style: baseStyle)];

    final spans = <TextSpan>[];
    int cursor = 0;

    for (final (start, end) in merged) {
      if (start > cursor) {
        spans.add(TextSpan(text: body.substring(cursor, start), style: baseStyle));
      }
      spans.add(TextSpan(text: body.substring(start, end), style: highlightStyle));
      cursor = end;
    }

    if (cursor < body.length) {
      spans.add(TextSpan(text: body.substring(cursor), style: baseStyle));
    }

    return spans;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DefendraColors.card,
        border: Border.all(color: DefendraColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: RichText(
        text: TextSpan(children: _buildSpans(record.body)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Triggered rules card
// ---------------------------------------------------------------------------

class _RulesCard extends StatelessWidget {
  const _RulesCard({required this.rules});

  final List<String> rules;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DefendraColors.card,
        border: Border.all(color: DefendraColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('why this was flagged', style: DefendraType.label),
          const SizedBox(height: 10),
          for (final rule in rules) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('> ', style: DefendraType.monoSmall.copyWith(
                  color: DefendraColors.suspicious,
                )),
                Expanded(
                  child: Text(rule, style: DefendraType.monoSmall.copyWith(
                    color: DefendraColors.text,
                  )),
                ),
              ],
            ),
            if (rule != rules.last) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Metadata footer
// ---------------------------------------------------------------------------

class _MetadataFooter extends StatelessWidget {
  const _MetadataFooter({required this.record});

  final ScanRecord record;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatTimestamp(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '${dt.day} ${_months[dt.month - 1]} ${dt.year}  $h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _formatTimestamp(record.timestamp),
          style: DefendraType.monoSmall,
        ),
        if (record.simSlot > 0) ...[
          const SizedBox(height: 4),
          Text(
            'SIM ${record.simSlot + 1}',
            style: DefendraType.monoSmall,
          ),
        ],
      ],
    );
  }
}
