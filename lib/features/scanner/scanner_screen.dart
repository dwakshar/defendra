import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
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

    // Fire haptic when a scam result arrives
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
              Text(
                'Built like a terminal. Trusted like a vault.',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: context.dMuted,
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
              // Animated verdict / error reveal
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
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
                            padding: const EdgeInsets.only(top: 20),
                            child: _ResultCard(result: state.result!),
                          )
                        : const SizedBox.shrink(key: ValueKey('empty')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Result card
// ---------------------------------------------------------------------------

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
        color: context.dSurface,
        border: Border.all(color: context.dBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: _accent, shape: BoxShape.circle),
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
                style: context.dtMonoSmall,
              ),
            ],
          ),
          if (result.triggerPhrases.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'SIGNALS',
              style: GoogleFonts.inter(
                fontSize: 10,
                color: context.dMuted,
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
                    color: context.dText,
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
