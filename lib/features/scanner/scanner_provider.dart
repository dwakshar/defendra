import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../ml/ml_engine.dart';

class ScannerState {
  final bool isLoading;
  final ScanResult? result;
  final String? error;

  const ScannerState({
    this.isLoading = false,
    this.result,
    this.error,
  });
}

class ScannerNotifier extends StateNotifier<ScannerState> {
  final MlEngine _engine = MlEngine();

  ScannerNotifier() : super(const ScannerState()) {
    _init();
  }

  Future<void> _init() async {
    state = const ScannerState(isLoading: true);
    try {
      await _engine.load();
      state = const ScannerState();
    } catch (e) {
      state = ScannerState(error: 'Model failed to load: $e');
    }
  }

  Future<void> scan(String text) async {
    if (!_engine.isReady) return;
    state = const ScannerState(isLoading: true);
    try {
      final result = _engine.scan(text);
      state = ScannerState(result: result);
    } catch (e) {
      state = ScannerState(error: e.toString());
    }
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
