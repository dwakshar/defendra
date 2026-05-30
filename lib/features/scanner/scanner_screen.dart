import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../data/models/scan_record.dart';
import '../../ml/ml_engine.dart';
import '../detail/detail_screen.dart';
import '../inbox/inbox_provider.dart';
import 'sample_messages.dart';
import 'scanner_provider.dart';

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  final _controller = TextEditingController();
  String _lastScannedText = '';
  bool _inputEmpty = true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final empty = _controller.text.trim().isEmpty;
      if (empty != _inputEmpty) setState(() => _inputEmpty = empty);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scan() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      _lastScannedText = text;
      ref.read(scannerProvider.notifier).scan(text);
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && mounted) {
      _controller.text = data!.text!;
      _controller.selection =
          TextSelection.collapsed(offset: _controller.text.length);
    }
  }

  void _loadSample(String text) {
    _controller.text = text;
    _controller.selection =
        TextSelection.collapsed(offset: text.length);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scannerProvider);
    final notifier = ref.read(scannerProvider.notifier);
    final recentRecords =
        ref.watch(inboxNotifierProvider).take(3).toList();

    ref.listen<ScannerState>(scannerProvider, (prev, next) {
      if (next.result != null &&
          prev?.result == null &&
          next.result!.label == ScamLabel.digitalArrest) {
        HapticFeedback.mediumImpact();
      }
    });

    return Scaffold(
      backgroundColor: context.dCanvas,
      appBar: AppBar(
        backgroundColor: context.dSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: context.dBorder),
        ),
        title: const Text('SCAN'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _controller,
                maxLines: 6,
                minLines: 4,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 13,
                  color: context.dText,
                  height: 1.5,
                ),
                decoration: InputDecoration(
                  hintText: 'Paste SMS here...',
                  hintStyle: GoogleFonts.jetBrainsMono(
                    fontSize: 13,
                    color: context.dMuted,
                  ),
                  filled: true,
                  fillColor: context.dSurface,
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: context.dBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: context.dBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: context.dBorder),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Built like a terminal. Trusted like a vault.',
                      style: GoogleFonts.inter(
                          fontSize: 11, color: context.dMuted),
                    ),
                  ),
                  if (_inputEmpty)
                    GestureDetector(
                      onTap: _pasteFromClipboard,
                      child: Text(
                        'Paste from clipboard',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: context.dMuted,
                          decoration: TextDecoration.underline,
                          decorationColor: context.dMuted,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: state.isLoading ? null : _scan,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: context.dCard,
                    disabledBackgroundColor: context.dCard,
                    side: BorderSide(color: context.dBorder),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: state.isLoading
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: context.dMuted,
                          ),
                        )
                      : Text(
                          'SCAN',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: context.dText,
                            letterSpacing: 2,
                          ),
                        ),
                ),
              ),
              // Animated result / example chips / error
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.04),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: state.error != null
                    ? Padding(
                        key: const ValueKey('err'),
                        padding: const EdgeInsets.only(top: 20),
                        child: Text(
                          state.error!,
                          style: context.dtMonoSmall.copyWith(
                            color: DefendraColors.scam,
                            fontSize: 11,
                          ),
                        ),
                      )
                    : state.result != null
                        ? Padding(
                            key: ValueKey(state.result!.label.index),
                            padding: const EdgeInsets.only(top: 16),
                            child: _ResultCard(
                              result: state.result!,
                              scannedText: _lastScannedText,
                              isSaved: state.isSaved,
                              onSave: () {
                                final record = ScanRecord(
                                  id: ScanRecord.generateId(),
                                  sender: 'Manual scan',
                                  body: _lastScannedText,
                                  verdict: state.result!.verdict,
                                  confidence: state.result!.confidence,
                                  triggeredRules:
                                      state.result!.triggerPhrases,
                                  category:
                                      state.result!.label.categoryId,
                                  timestamp: DateTime.now(),
                                );
                                ref
                                    .read(inboxNotifierProvider.notifier)
                                    .saveManual(record);
                                notifier.markSaved();
                              },
                            ),
                          )
                        : _inputEmpty && !state.isLoading
                            ? Padding(
                                key: const ValueKey('chips'),
                                padding: const EdgeInsets.only(top: 20),
                                child: _ExampleChips(onSelect: _loadSample),
                              )
                            : const SizedBox.shrink(
                                key: ValueKey('empty')),
              ),
              // Recent scans
              if (recentRecords.isNotEmpty) ...[
                const SizedBox(height: 28),
                Text(
                  'RECENT',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: context.dMuted,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                ...recentRecords.map((r) => _RecentRow(record: r)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Example chips — empty-state only
// ---------------------------------------------------------------------------

class _ExampleChips extends StatelessWidget {
  final void Function(String) onSelect;
  const _ExampleChips({required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TRY AN EXAMPLE',
          style: GoogleFonts.inter(
            fontSize: 10,
            color: context.dMuted,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: sampleMessages.entries.map((e) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => onSelect(e.value),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: context.dCard,
                      border: Border.all(color: context.dBorder),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      e.key,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        color: context.dText,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Inline result card
// ---------------------------------------------------------------------------

class _ResultCard extends StatelessWidget {
  final ScanResult result;
  final String scannedText;
  final bool isSaved;
  final VoidCallback onSave;

  const _ResultCard({
    required this.result,
    required this.scannedText,
    required this.isSaved,
    required this.onSave,
  });

  Color get _dotColor {
    switch (result.verdict) {
      case Verdict.safe:
        return DefendraColors.safe;
      case Verdict.suspicious:
        return DefendraColors.suspicious;
      case Verdict.scam:
        return DefendraColors.scam;
    }
  }

  String get _verdictLabel {
    switch (result.verdict) {
      case Verdict.safe:
        return 'SAFE';
      case Verdict.suspicious:
        return 'SUSPICIOUS';
      case Verdict.scam:
        return 'SCAM';
    }
  }

  ScanRecord _buildRecord() => ScanRecord(
        id: ScanRecord.generateId(),
        sender: 'Manual scan',
        body: scannedText,
        verdict: result.verdict,
        confidence: result.confidence,
        triggeredRules: result.triggerPhrases,
        category: result.label.categoryId,
        timestamp: DateTime.now(),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.dSurface,
        border: Border.all(color: context.dBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Verdict header
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                    color: _dotColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                _verdictLabel,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _dotColor,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              if (result.ruleOverride) ...[
                Text(
                  'RULE OVERRIDE',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: DefendraColors.suspicious,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Text(
                '${(result.confidence * 100).toStringAsFixed(1)}%',
                style: context.dtMonoSmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Category
          Text(
            result.label.labelDisplay,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: context.dMuted,
              height: 1.4,
            ),
          ),
          // Signal chips
          if (result.triggerPhrases.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: result.triggerPhrases.map((phrase) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: context.dCard,
                    border: Border.all(color: context.dBorder),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    phrase,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: context.dMuted,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 14),
          // Actions
          Row(
            children: [
              _ActionButton(
                label: 'View details',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DetailScreen(record: _buildRecord()),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              _ActionButton(
                label: isSaved ? 'Saved' : 'Save to inbox',
                dimmed: isSaved,
                onTap: isSaved ? null : onSave,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool dimmed;

  const _ActionButton({
    required this.label,
    this.onTap,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 12,
          color: dimmed ? context.dMuted : context.dText,
          decoration: dimmed ? null : TextDecoration.underline,
          decorationColor: context.dText,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recent scan row
// ---------------------------------------------------------------------------

class _RecentRow extends StatelessWidget {
  final ScanRecord record;
  const _RecentRow({required this.record});

  Color _dotColor() {
    switch (record.verdict) {
      case Verdict.safe:
        return DefendraColors.safe;
      case Verdict.suspicious:
        return DefendraColors.suspicious;
      case Verdict.scam:
        return DefendraColors.scam;
    }
  }

  String _relativeTime() {
    final diff = DateTime.now().difference(record.timestamp);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DetailScreen(record: record)),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.dBorder)),
        ),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                  color: _dotColor(), shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                record.body,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    fontSize: 12, color: context.dText),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _relativeTime(),
              style: GoogleFonts.inter(
                  fontSize: 11, color: context.dMuted),
            ),
          ],
        ),
      ),
    );
  }
}
