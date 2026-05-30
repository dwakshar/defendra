import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../data/models/scan_record.dart';
import '../../ml/explanation.dart';
import '../../ml/rule_matcher.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key, required this.record});
  final ScanRecord record;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ctrl.forward();
      if (widget.record.verdict == Verdict.scam) {
        HapticFeedback.lightImpact();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final explanation = RuleMatcher.explain(widget.record.body);

    return Scaffold(
      backgroundColor: context.dCanvas,
      appBar: AppBar(
        backgroundColor: context.dCanvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: context.dMuted),
        title: Text(
          widget.record.sender,
          style: context.dtMono.copyWith(fontSize: 13),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: FadeTransition(
        opacity: _fade,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            _VerdictHeader(record: widget.record),
            const SizedBox(height: 16),
            _SmsBodyCard(
                body: widget.record.body, spans: explanation.spans),
            if (explanation.signals.isNotEmpty) ...[
              const SizedBox(height: 16),
              _SignalsPanel(signals: explanation.signals),
              const SizedBox(height: 12),
              _ReasonPanel(reason: explanation.reason),
            ],
            const SizedBox(height: 16),
            _ActionsRow(record: widget.record),
            const SizedBox(height: 20),
            _MetadataFooter(record: widget.record),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Verdict header — Hero dot + label + confidence
// ---------------------------------------------------------------------------

class _VerdictHeader extends StatelessWidget {
  const _VerdictHeader({required this.record});
  final ScanRecord record;

  Color get _dot => switch (record.verdict) {
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: context.dCard,
        border: Border.all(color: context.dBorder, width: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // Hero dot — destination matches inbox _ScanCard source
          Hero(
            tag: 'dot_${record.id}',
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: _dot, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: context.dText,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          Text(
            '${(record.confidence * 100).toStringAsFixed(1)}%',
            style: context.dtMonoSmall,
          ),
          const SizedBox(width: 8),
          Text(record.category, style: context.dtMonoSmall),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SMS body — RichText with dashed red underlines on matched spans
// ---------------------------------------------------------------------------

class _SmsBodyCard extends StatelessWidget {
  const _SmsBodyCard({required this.body, required this.spans});
  final String body;
  final List<TriggerSpan> spans;

  List<TextSpan> _buildSpans(BuildContext context) {
    final base = GoogleFonts.jetBrainsMono(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: context.dText,
      height: 1.65,
    );
    final flagged = base.copyWith(
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.dashed,
      decorationColor: DefendraColors.scam,
      decorationThickness: 1.5,
    );

    if (spans.isEmpty) return [TextSpan(text: body, style: base)];

    final result = <TextSpan>[];
    int cursor = 0;
    for (final span in spans) {
      if (span.start > cursor) {
        result.add(TextSpan(
            text: body.substring(cursor, span.start), style: base));
      }
      result.add(TextSpan(
          text: body.substring(span.start, span.end), style: flagged));
      cursor = span.end;
    }
    if (cursor < body.length) {
      result.add(TextSpan(text: body.substring(cursor), style: base));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.dCard,
        border: Border.all(color: context.dBorder, width: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: RichText(text: TextSpan(children: _buildSpans(context))),
    );
  }
}

// ---------------------------------------------------------------------------
// Signals chips
// ---------------------------------------------------------------------------

class _SignalsPanel extends StatelessWidget {
  const _SignalsPanel({required this.signals});
  final List<String> signals;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('signals', style: context.dtMonoSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: signals.map((key) => _Chip(label: key)).toList(),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.dCard,
        border: Border.all(color: context.dBorder, width: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 11,
          fontWeight: FontWeight.w400,
          color: context.dMuted,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reason sentence
// ---------------------------------------------------------------------------

class _ReasonPanel extends StatelessWidget {
  const _ReasonPanel({required this.reason});
  final String reason;

  @override
  Widget build(BuildContext context) {
    return Text(
      reason,
      style: context.dtMono.copyWith(
        color: context.dMuted,
        fontSize: 13,
        height: 1.55,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Actions row
// ---------------------------------------------------------------------------

class _ActionsRow extends StatelessWidget {
  const _ActionsRow({required this.record});
  final ScanRecord record;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            label: 'Report 1930',
            onTap: () => _showSnack(
                context, 'Call 1930 — India Cyber Fraud Helpline'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ActionButton(
            label: 'Block sender',
            onTap: () => _showSnack(
                context, 'Open your dialer to block ${record.sender}'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ActionButton(
            label: 'Share',
            onTap: () => _shareWarning(context),
          ),
        ),
      ],
    );
  }

  void _showSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: context.dtMonoSmall.copyWith(color: context.dText),
        ),
        backgroundColor: context.dCard,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: context.dBorder, width: 0.5),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _shareWarning(BuildContext context) async {
    final warning =
        '[Defendra] Scam SMS from ${record.sender}:\n\n"${record.body}"\n\n'
        'Verdict: ${record.verdict.name.toUpperCase()} '
        '(${(record.confidence * 100).toStringAsFixed(0)}% confidence).\n'
        'Report scams: 1930 | cybercrime.gov.in';
    await Clipboard.setData(ClipboardData(text: warning));
    if (context.mounted) {
      _showSnack(context, 'Warning copied to clipboard');
    }
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.transparent,
          border: Border.all(color: context.dBorder, width: 0.5),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            fontWeight: FontWeight.w400,
            color: context.dMuted,
          ),
          overflow: TextOverflow.ellipsis,
        ),
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

  String _fmt(DateTime dt) {
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
        Text(_fmt(record.timestamp), style: context.dtMonoSmall),
        if (record.simSlot > 0) ...[
          const SizedBox(height: 4),
          Text('SIM ${record.simSlot + 1}', style: context.dtMonoSmall),
        ],
      ],
    );
  }
}
