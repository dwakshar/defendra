import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/colors.dart';
import '../../ml/ml_engine.dart';
import 'scanner_provider.dart';

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scannerProvider);
    final notifier = ref.read(scannerProvider.notifier);

    return Scaffold(
      backgroundColor: DefendraColors.canvas,
      appBar: AppBar(
        backgroundColor: DefendraColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: DefendraColors.border),
        ),
        title: Text(
          'Defendra',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: DefendraColors.text,
          ),
        ),
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
                  color: DefendraColors.text,
                  height: 1.5,
                ),
                decoration: InputDecoration(
                  hintText: 'Paste SMS here...',
                  hintStyle: GoogleFonts.jetBrainsMono(
                    fontSize: 13,
                    color: DefendraColors.muted,
                  ),
                  filled: true,
                  fillColor: DefendraColors.surface,
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: DefendraColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: DefendraColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: DefendraColors.border),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Built like a terminal. Trusted like a vault.',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: DefendraColors.muted,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: state.isLoading
                      ? null
                      : () {
                          final text = _controller.text.trim();
                          if (text.isNotEmpty) notifier.scan(text);
                        },
                  style: OutlinedButton.styleFrom(
                    backgroundColor: DefendraColors.card,
                    disabledBackgroundColor: DefendraColors.card,
                    side: const BorderSide(color: DefendraColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: state.isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: DefendraColors.muted,
                          ),
                        )
                      : Text(
                          'SCAN',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: DefendraColors.text,
                            letterSpacing: 2,
                          ),
                        ),
                ),
              ),
              if (state.error != null) ...[
                const SizedBox(height: 20),
                Text(
                  state.error!,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: DefendraColors.scam,
                  ),
                ),
              ],
              if (state.result != null) ...[
                const SizedBox(height: 20),
                _ResultCard(result: state.result!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final ScanResult result;

  const _ResultCard({required this.result});

  Color get _accent {
    switch (result.label) {
      case ScamLabel.safe:
        return DefendraColors.safe;
      case ScamLabel.otpKyc:
      case ScamLabel.deliveryCourier:
        return DefendraColors.suspicious;
      case ScamLabel.digitalArrest:
        return DefendraColors.scam;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DefendraColors.surface,
        border: Border.all(color: DefendraColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Verdict row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                result.label.labelDisplay.toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _accent,
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
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: DefendraColors.muted,
                ),
              ),
            ],
          ),
          // Signals section
          if (result.triggerPhrases.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'SIGNALS',
              style: GoogleFonts.inter(
                fontSize: 10,
                color: DefendraColors.muted,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 6),
            ...result.triggerPhrases.map(
              (phrase) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '— $phrase',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: DefendraColors.text,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
