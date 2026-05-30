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

  Future<void> _init() async {
    state = const ScannerState(isLoading: true);
    await _engine.load();
    if (_engine.loadError != null) {
      state = ScannerState(error: 'Model failed to load: ${_engine.loadError}');
    } else {
      state = const ScannerState();
    }
  }

  Future<void> scan(String text) async {
    if (!_engine.isReady) return;
    state = const ScannerState(isLoading: true);
    try {
      final result = await _engine.scan(text);
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
