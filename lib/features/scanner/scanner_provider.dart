import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/scan_record.dart';
import '../../ml/ml_engine.dart';
import '../../ml/ml_engine_provider.dart';
import '../../ml/rule_matcher.dart';

class ScannerState {
  final bool isLoading;
  final ScanResult? result;
  final String? error;
  final bool isSaved;

  const ScannerState({
    this.isLoading = false,
    this.result,
    this.error,
    this.isSaved = false,
  });
}

class ScannerNotifier extends StateNotifier<ScannerState> {
  ScannerNotifier(this._ref) : super(const ScannerState());

  final Ref _ref;

  // preset constructor kept for tests that inject pre-built state.
  ScannerNotifier.preset(ScannerState s, Ref ref)
      : _ref = ref,
        super(s);

  Future<void> scan(String text) async {
    state = const ScannerState(isLoading: true);
    try {
      final result = await _classify(text);
      state = ScannerState(result: result);
    } catch (e) {
      state = ScannerState(error: e.toString());
    }
  }

  void markSaved() {
    state = ScannerState(result: state.result, isSaved: true);
  }

  Future<ClassificationResult> _classify(String text) async {
    try {
      final engine = await _ref.read(mlEngineProvider.future);
      return engine.classify(text);
    } catch (_) {
      // Engine dead or still loading — rule-only so scan always produces output.
      final (:reasons, :keys) = RuleMatcher.matchAll(text);
      return ClassificationResult(
        verdict: keys.isNotEmpty ? Verdict.suspicious : Verdict.safe,
        pScam: double.nan,
        probs: const [],
        source: VerdictSource.ruleFallback,
        triggers: keys,
        triggerReasons: reasons,
      );
    }
  }
}

final scannerProvider = StateNotifierProvider<ScannerNotifier, ScannerState>(
  (ref) => ScannerNotifier(ref),
);
