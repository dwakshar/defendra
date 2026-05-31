import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../ml/ml_engine.dart';

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
  final MlEngine _engine = MlEngine();

  ScannerNotifier() : super(const ScannerState()) {
    _init();
  }

  @visibleForTesting
  ScannerNotifier.preset(ScannerState s) : super(s);

  Future<void> _init() async {
    state = const ScannerState(isLoading: true);
    await _engine.load();
    if (_engine.loadError != null) {
      state = ScannerState(error: 'Model failed to load: ${_engine.loadError}');
    } else {
      state = const ScannerState();
      if (kDebugMode) {
        final r = await _engine.benchmark(runs: 10);
        debugPrint('[BENCHMARK]\n$r');
      }
    }
  }

  Future<void> scan(String text) async {
    state = const ScannerState(isLoading: true);
    try {
      // classify() has a built-in rule-based fallback when the model is not
      // ready, so scans work even if the TFLite model failed to load.
      final result = await _engine.classify(text);
      state = ScannerState(result: result);
    } catch (e) {
      state = ScannerState(error: e.toString());
    }
  }

  void markSaved() {
    state = ScannerState(result: state.result, isSaved: true);
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }
}

final scannerProvider =
    StateNotifierProvider<ScannerNotifier, ScannerState>(
  (ref) => ScannerNotifier(),
);
