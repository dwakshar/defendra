import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_litert/flutter_litert.dart';
import 'package:path_provider/path_provider.dart';

import '../data/models/scan_record.dart';
import 'dart_tokenizer.dart';
import 'rule_matcher.dart';

const int _kSeqLen = 96;

// ScanResult is a zero-cost alias so scanner_screen / inbox_provider compile
// without field renames. Both names refer to the same class.
typedef ScanResult = ClassificationResult;

class ClassificationResult {
  final Verdict verdict;

  // NaN when source == ruleFallback (model did not run).
  final double pScam;

  // [4] softmax probs ordered [safe, otp_kyc, delivery_courier, digital_arrest].
  // Empty when source == ruleFallback.
  final List<double> probs;

  final VerdictSource source;

  // Rule-matcher signal keys (snake_case).
  final List<String> triggers;

  // Human-readable reason strings for UI chips.
  final List<String> triggerReasons;

  const ClassificationResult({
    required this.verdict,
    required this.pScam,
    required this.probs,
    required this.source,
    required this.triggers,
    required this.triggerReasons,
  });

  String get category {
    if (verdict == Verdict.safe) return 'safe';
    if (triggers.contains('digital_arrest')) return 'digital_arrest';
    if (triggers.contains('delivery_fee')) return 'delivery';
    if (triggers.contains('lottery')) return 'lottery';
    if (triggers.contains('job_scam')) return 'job';
    if (triggers.contains('kyc_fraud') ||
        triggers.contains('bank_impersonation')) {
      return 'kyc';
    }
    if (triggers.contains('otp_request')) return 'otp';
    return switch (label) {
      ScamLabel.deliveryCourier => 'delivery',
      ScamLabel.digitalArrest => 'digital_arrest',
      _ => 'kyc',
    };
  }

  double get confidence {
    if (verdict == Verdict.safe) return probs.isNotEmpty ? probs[0] : 0.0;
    return pScam.isNaN ? 0.0 : pScam;
  }

  List<String> get firedSignalKeys => triggers;

  // isError kept for any caller that checks it; always false on this type.
  bool get isError => false;

  ScamLabel get label {
    if (probs.isEmpty) return ScamLabel.safe;
    if (verdict == Verdict.safe) return ScamLabel.safe;
    int idx = 1;
    for (int i = 2; i <= 3; i++) {
      if (probs[i] > probs[idx]) idx = i;
    }
    return ScamLabel.values[idx];
  }

  bool get ruleOverride => source == VerdictSource.ruleFallback;

  List<String> get triggerPhrases => triggerReasons;
}

// ---------------------------------------------------------------------------
// MlEngine
// ---------------------------------------------------------------------------

class MlEngine {
  // Inference runs on the Kotlin/Java side via this channel.
  // The Java com.google.ai.edge.litert.Interpreter does NOT auto-apply
  // XNNPACK, unlike the C API (flutter_litert) which unconditionally applies
  // the built-in delegate and then nullifies tensor 120's data.raw.
  static const _channel = MethodChannel('com.defendra/ml');

  DartTokenizer? _tok;
  bool _healthy = false;
  String? _loadError;

  MlEngine();

  // Primary factory — called by mlEngineProvider after the Java model is
  // loaded and warmed up via the Kotlin channel.
  factory MlEngine.loaded(DartTokenizer tok) =>
      MlEngine().._tok = tok.._healthy = true;

  bool get isReady => _healthy;

  String? get loadError => _loadError;

  // ---------------------------------------------------------------------------
  // classify
  // ---------------------------------------------------------------------------

  Future<ClassificationResult> classify(String text) async {
    final (:reasons, :keys) = RuleMatcher.matchAll(text);
    final signal = keys.isNotEmpty;

    if (!_healthy) {
      return ClassificationResult(
        verdict: signal ? Verdict.suspicious : Verdict.safe,
        pScam: double.nan,
        probs: const [],
        source: VerdictSource.ruleFallback,
        triggers: keys,
        triggerReasons: reasons,
      );
    }

    final logits = await _runInference(_tok!, text);
    final probs = _softmax(logits);
    final pScam = probs[1] + probs[2] + probs[3];

    final Verdict verdict;
    if (pScam > 0.85 && signal) {
      verdict = Verdict.scam;
    } else if (pScam >= 0.50 && signal) {
      verdict = Verdict.suspicious;
    } else {
      verdict = Verdict.safe;
    }

    debugPrint(
      '[ML] classify  pScam=${pScam.toStringAsFixed(3)}  '
      'verdict=$verdict  signal=$signal  keys=$keys',
    );

    return ClassificationResult(
      verdict: verdict,
      pScam: pScam,
      probs: probs,
      source: VerdictSource.ml,
      triggers: keys,
      triggerReasons: reasons,
    );
  }

  void dispose() {
    _tok = null;
    _healthy = false;
  }

  // Backward-compat wrapper: swallows errors into loadError.
  Future<void> load({String asset = 'assets/ml/defendra_int8.tflite'}) async {
    try {
      await loadModel(asset: asset);
    } catch (e, st) {
      _healthy = false;
      _loadError = e.toString();
      debugPrint('[ML-LOAD-ERR] $e');
      debugPrintStack(label: '[ML-LOAD-ERR]', stackTrace: st);
    }
  }

  // ---------------------------------------------------------------------------
  // loadModel — backup path that mirrors mlEngineProvider logic.
  // Uses the Kotlin channel (Java API) for inference to avoid XNNPACK.
  // ---------------------------------------------------------------------------

  Future<void> loadModel({
    String asset = 'assets/ml/defendra_int8.tflite',
  }) async {
    final data = await rootBundle.load(asset);
    final bytes = data.buffer.asUint8List();

    // dtype checks via C API (isolate not available here, use main thread).
    // Close immediately — never invoke through the C API interpreter.
    final options = InterpreterOptions();
    final interp = Interpreter.fromBuffer(bytes, options: options);
    void assertType(String label, TensorType actual, TensorType expected) {
      if (actual != expected) {
        interp.close();
        throw MlEngineDeadException(
          '$label dtype: expected $expected, got $actual',
        );
      }
    }
    assertType('input[0]', interp.getInputTensor(0).type, TensorType.int64);
    assertType('input[1]', interp.getInputTensor(1).type, TensorType.int64);
    assertType('output[0]', interp.getOutputTensor(0).type, TensorType.float32);
    interp.close();
    debugPrint('[ML] dtype checks OK');

    // Copy to file for Java API.
    final supportDir = await getApplicationSupportDirectory();
    final modelFile = File('${supportDir.path}/defendra_int8.tflite');
    final alreadyCopied =
        await modelFile.exists() && (await modelFile.length()) == bytes.length;
    if (!alreadyCopied) {
      await modelFile.writeAsBytes(bytes, flush: true);
    }

    // Load on the Java side (no XNNPACK).
    try {
      await _channel.invokeMethod<void>('loadModel', modelFile.path);
    } on PlatformException catch (e) {
      throw MlEngineDeadException('Java loadModel failed: ${e.message}');
    }

    // Load tokenizer.
    final vocabJson = await rootBundle.loadString('assets/ml/vocab.json');
    final parsed = json.decode(vocabJson) as Map<String, dynamic>;
    final tok = DartTokenizer.fromVocab(
      parsed.map((k, v) => MapEntry(k, (v as num).toInt())),
    );

    // Warmup via channel.
    try {
      final r = await _channel.invokeListMethod<double>('infer', {
        'ids': Int64List(_kSeqLen),
        'mask': Int64List(_kSeqLen),
      });
      if (r == null || r.length != 4) {
        throw MlEngineDeadException('Warmup returned unexpected: $r');
      }
      debugPrint('[ML] warmup OK: $r');
    } on PlatformException catch (e) {
      throw MlEngineDeadException('Warmup failed: ${e.message}');
    }

    _tok = tok;
    _healthy = true;
    _loadError = null;
    debugPrint('[ML] loadModel OK  asset=$asset');
  }

  Future<ClassificationResult> scan(String text) => classify(text);

  // ---------------------------------------------------------------------------
  // Inference — runs via Kotlin method channel (Java API, CPU-only, no XNNPACK).
  // ---------------------------------------------------------------------------

  Future<List<double>> _runInference(DartTokenizer tok, String text) {
    final tokens = tok.tokenize(text, maxLength: _kSeqLen);
    return _runInferenceFromTokens(
      tokens['input_ids']!,
      tokens['attention_mask']!,
    );
  }

  Future<List<double>> _runInferenceFromTokens(
    List<int> ids,
    List<int> mask,
  ) async {
    final inputIds = Int64List(_kSeqLen);
    final attnMask = Int64List(_kSeqLen);
    for (int j = 0; j < _kSeqLen; j++) {
      inputIds[j] = ids[j];
      attnMask[j] = mask[j];
    }

    final List<double>? result;
    try {
      result = await _channel.invokeListMethod<double>('infer', {
        'ids': inputIds,
        'mask': attnMask,
      });
    } on PlatformException catch (e) {
      throw MlEngineDeadException('infer channel error: ${e.message}');
    }

    if (result == null || result.length != 4) {
      throw MlEngineDeadException('infer returned unexpected result: $result');
    }
    debugPrint('[ML] RAW LOGITS: $result');
    return result;
  }

  static List<double> _softmax(List<double> logits) {
    final maxVal = logits.reduce(max);
    final exps = logits.map((v) => exp(v - maxVal)).toList(growable: false);
    final sum = exps.fold(0.0, (a, b) => a + b);
    return List<double>.unmodifiable(exps.map((v) => v / sum));
  }
}

class MlEngineDeadException implements Exception {
  final String message;
  const MlEngineDeadException(this.message);
  @override
  String toString() => 'MlEngineDeadException: $message';
}

// ---------------------------------------------------------------------------
// ScamLabel
// ---------------------------------------------------------------------------

enum ScamLabel { safe, otpKyc, deliveryCourier, digitalArrest }

enum VerdictSource { ml, ruleFallback }

extension ScamLabelExt on ScamLabel {
  String get categoryId => switch (this) {
    ScamLabel.safe => 'none',
    ScamLabel.otpKyc => 'otp_kyc',
    ScamLabel.deliveryCourier => 'delivery_courier',
    ScamLabel.digitalArrest => 'digital_arrest',
  };

  bool get isScam => this != ScamLabel.safe;

  String get labelDisplay => switch (this) {
    ScamLabel.safe => 'Safe',
    ScamLabel.otpKyc => 'OTP / KYC Scam',
    ScamLabel.deliveryCourier => 'Delivery Scam',
    ScamLabel.digitalArrest => 'Digital Arrest',
  };
}
