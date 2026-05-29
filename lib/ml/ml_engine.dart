import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'dart_tokenizer.dart';
import 'rule_matcher.dart';

// ---------------------------------------------------------------------------
// Isolate worker — top-level so compute() can transfer it across isolates.
// Receives serialisable args; creates its own Interpreter and tokenizer
// (no rootBundle access in isolates).
// ---------------------------------------------------------------------------

Future<List<double>> _classifyInIsolate(Map<String, dynamic> args) async {
  final modelBytes = args['modelBytes'] as Uint8List;
  final vocabJson = args['vocabJson'] as String;
  final text = args['text'] as String;

  final Map<String, dynamic> parsed = json.decode(vocabJson);
  final vocab = parsed.map((k, v) => MapEntry(k, (v as num).toInt()));
  final tokenizer = DartTokenizer.fromVocab(vocab);

  final interpreter = Interpreter.fromBuffer(modelBytes);
  interpreter.allocateTensors();

  try {
    final tokens = tokenizer.tokenize(text);
    print(
      'FLUTTER: ${tokens['input_ids']!.take(20).toList()}',
    ); // ← add this line
    return _infer(interpreter, tokens);
  } finally {
    interpreter.close();
  }
}

// Shared inference kernel — used by both the main-thread path (scan) and the
// isolate path (_classifyInIsolate).  Expects a freshly allocated interpreter.
List<double> _infer(Interpreter interpreter, Map<String, List<int>> tokens) {
  // Input shape [1, 96] — wrap each flat list in a batch dimension.
  final inputIds = [tokens['input_ids']!];
  final attentionMask = [tokens['attention_mask']!];

  // Output shape [1, 4] — tflite_flutter populates the nested list in-place.
  final output = List.generate(1, (_) => List<double>.filled(4, 0.0));
  interpreter.runForMultipleInputs([inputIds, attentionMask], {0: output});

  return List<double>.from(output[0]);
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

class MlEngine {
  Interpreter? _interpreter;
  final DartTokenizer _tokenizer = DartTokenizer();

  // Kept as fields so classify() can ship them to the isolate without
  // touching rootBundle again.
  late Uint8List _modelBytes;
  late String _vocabJson;

  bool _ready = false;
  bool get isReady => _ready;

  /// Async — runs inference in a Dart isolate via compute().
  /// Use from the live SMS pipeline so the main thread stays unblocked.
  Future<ScanResult> classify(String text) async {
    _assertReady();
    final rules = RuleMatcher.match(text);

    try {
      final logits = await compute(_classifyInIsolate, {
        'modelBytes': _modelBytes,
        'vocabJson': _vocabJson,
        'text': text,
      });
      debugPrint('[LOGITS-classify] $logits');
      return _buildResult(logits, rules);
    } catch (e, st) {
      debugPrint('[ML-ERR] classify failed: $e');
      debugPrintStack(label: '[ML-ERR]', stackTrace: st);
      return _fallback(rules);
    }
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _ready = false;
  }

  /// Loads model bytes and vocab, wires up the main-thread interpreter.
  Future<void> load() async {
    final byteData = await rootBundle.load('assets/ml/model.tflite');
    _modelBytes = byteData.buffer.asUint8List();
    _vocabJson = await rootBundle.loadString('assets/ml/vocab.json');

    _interpreter = Interpreter.fromBuffer(_modelBytes);
    _interpreter!.allocateTensors();
    await _tokenizer.load();

    if (kDebugMode) {
      _logTensors();
    }

    _ready = true;
  }

  /// Synchronous — runs inference on the caller thread.
  /// Use from the scanner screen where latency is bound to the UI frame.
  ScanResult scan(String text) {
    _assertReady();
    final rules = RuleMatcher.match(text);
    final tokens = _tokenizer.tokenize(text);
    final logits = _infer(_interpreter!, tokens);
    debugPrint('[LOGITS-scan] $logits');
    return _buildResult(logits, rules);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  void _assertReady() {
    if (!_ready || _interpreter == null)
      throw StateError('MlEngine not loaded');
  }

  ScanResult _buildResult(List<double> logits, List<String> rules) {
    if (logits.length != ScamLabel.values.length) {
      throw StateError(
        'Unexpected logits length ${logits.length}; '
        'expected ${ScamLabel.values.length}.',
      );
    }

    print('RAW LOGITS: $logits'); // the 4 values straight from the model
    final probs = _softmax(logits);

    int maxIdx = 0;
    for (int i = 1; i < probs.length; i++) {
      if (probs[i] > probs[maxIdx]) maxIdx = i;
    }

    var label = ScamLabel.values[maxIdx];
    var confidence = probs[maxIdx];
    var ruleOverride = false;

    if (rules.isNotEmpty && label == ScamLabel.safe && confidence < 0.75) {
      label = ScamLabel.otpKyc;
      confidence = 0.75;
      ruleOverride = true;
    }

    return ScanResult(
      label: label,
      confidence: confidence,
      triggerPhrases: rules,
      ruleOverride: ruleOverride,
    );
  }

  ScanResult _fallback(List<String> rules) {
    if (rules.isNotEmpty) {
      return ScanResult(
        label: ScamLabel.otpKyc,
        confidence: 0.75,
        triggerPhrases: rules,
        ruleOverride: true,
      );
    }
    return const ScanResult(
      label: ScamLabel.safe,
      confidence: 0.0,
      triggerPhrases: [],
      ruleOverride: true,
    );
  }

  void _logTensors() {
    final inputs = _interpreter!.getInputTensors();
    final outputs = _interpreter!.getOutputTensors();
    for (int i = 0; i < inputs.length; i++) {
      final t = inputs[i];
      debugPrint('Input[$i]: name=${t.name} shape=${t.shape} type=${t.type}');
    }
    for (int i = 0; i < outputs.length; i++) {
      final t = outputs[i];
      debugPrint('Output[$i]: name=${t.name} shape=${t.shape} type=${t.type}');
    }
  }

  List<double> _softmax(List<double> logits) {
    final maxVal = logits.reduce(max);
    final exps = logits.map((v) => exp(v - maxVal)).toList();
    final sum = exps.fold(0.0, (a, b) => a + b);
    return exps.map((v) => v / sum).toList();
  }
}

// ---------------------------------------------------------------------------
// Domain types
// ---------------------------------------------------------------------------

enum ScamLabel { safe, otpKyc, deliveryCourier, digitalArrest }

class ScanResult {
  final ScamLabel label;
  final double confidence;
  final List<String> triggerPhrases;
  final bool ruleOverride;

  const ScanResult({
    required this.label,
    required this.confidence,
    required this.triggerPhrases,
    this.ruleOverride = false,
  });
}

extension ScamLabelExt on ScamLabel {
  bool get isScam => this != ScamLabel.safe;

  String get labelDisplay {
    switch (this) {
      case ScamLabel.safe:
        return 'Safe';
      case ScamLabel.otpKyc:
        return 'OTP / KYC Scam';
      case ScamLabel.deliveryCourier:
        return 'Delivery Scam';
      case ScamLabel.digitalArrest:
        return 'Digital Arrest';
    }
  }
}
