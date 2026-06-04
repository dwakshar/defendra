import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_litert/flutter_litert.dart';

import '../data/models/scan_record.dart';
import 'dart_tokenizer.dart';
import 'rule_matcher.dart';

const int _kSeqLen = 96;

enum VerdictSource { ml, ruleFallback }

class MlEngineDeadException implements Exception {
  final String message;
  const MlEngineDeadException(this.message);
  @override
  String toString() => 'MlEngineDeadException: $message';
}

class ClassificationResult {
  const ClassificationResult({
    required this.verdict,
    required this.pScam,
    required this.probs,
    required this.source,
    required this.triggers,
    required this.triggerReasons,
  });

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

  // ---------------------------------------------------------------------------
  // Derived accessors used by existing callers — no field renames required.
  // ---------------------------------------------------------------------------

  bool get ruleOverride => source == VerdictSource.ruleFallback;

  List<String> get triggerPhrases => triggerReasons;

  List<String> get firedSignalKeys => triggers;

  double get confidence {
    if (verdict == Verdict.safe) return probs.isNotEmpty ? probs[0] : 0.0;
    return pScam.isNaN ? 0.0 : pScam;
  }

  ScamLabel get label {
    if (probs.isEmpty) return ScamLabel.safe;
    // argmax over {1,2,3} for the scam category, then gate on verdict.
    if (verdict == Verdict.safe) return ScamLabel.safe;
    int idx = 1;
    for (int i = 2; i <= 3; i++) {
      if (probs[i] > probs[idx]) idx = i;
    }
    return ScamLabel.values[idx];
  }

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

  // isError kept for any caller that checks it; always false on this type.
  bool get isError => false;
}

// ScanResult is a zero-cost alias so scanner_screen / inbox_provider compile
// without field renames. Both names refer to the same class.
typedef ScanResult = ClassificationResult;

// ---------------------------------------------------------------------------
// MlEngine
// ---------------------------------------------------------------------------

class MlEngine {
  Interpreter? _interp;
  DartTokenizer? _tok;
  bool _healthy = false;
  String? _loadError;

  bool get isReady => _healthy;
  String? get loadError => _loadError;

  // ---------------------------------------------------------------------------
  // Factory used by mlEngineProvider after background-isolate verification.
  // The interpreter has already passed dtype checks and self-test; mark healthy
  // immediately without repeating the load work on the main thread.
  // ---------------------------------------------------------------------------

  factory MlEngine.loaded(Interpreter interp, DartTokenizer tok) =>
      MlEngine._fromLoaded(interp, tok);

  MlEngine._fromLoaded(Interpreter interp, DartTokenizer tok) {
    _interp = interp;
    _tok = tok;
    _healthy = true;
  }

  // ---------------------------------------------------------------------------
  // loadModel — allocates interpreter, asserts dtypes, runs self-test.
  // Throws MlEngineDeadException (or rethrows) on any failure.
  // Never marks healthy until the self-test passes.
  // ---------------------------------------------------------------------------

  Future<void> loadModel({
    String asset = 'assets/ml/defendra_int8.tflite',
  }) async {
    final interp = await Interpreter.fromAsset(asset);
    // fromAsset → fromBuffer → _create → Interpreter._ which calls
    // allocateTensors(); call again to be explicit per the spec.
    interp.allocateTensors();

    final in0 = interp.getInputTensor(0);
    final in1 = interp.getInputTensor(1);
    final out0 = interp.getOutputTensor(0);

    void assertType(String label, TensorType actual, TensorType expected) {
      if (actual != expected) {
        interp.close();
        throw MlEngineDeadException(
          '$label dtype: expected $expected, got $actual — '
          'int32-fed-as-int64 bug or wrong model export; fix the export, '
          'do not work around this assertion',
        );
      }
    }

    // These checks are the ONLY thing that prevents the silent int32 coercion
    // bug that produced uniform-random logits on every prior build.
    assertType('input[0]', in0.type, TensorType.int64);
    assertType('input[1]', in1.type, TensorType.int64);
    assertType('output[0]', out0.type, TensorType.float32);

    debugPrint(
      '[ML] tensors OK  '
      'in0=${in0.type}${in0.shape}  '
      'in1=${in1.type}${in1.shape}  '
      'out0=${out0.type}${out0.shape}',
    );

    // Tokenizer — pruned vocab, remapped embedding row indices.
    final vocabJson = await rootBundle.loadString('assets/ml/vocab_pruned.json');
    final parsed = json.decode(vocabJson) as Map<String, dynamic>;
    final tok = DartTokenizer.fromVocab(
      parsed.map((k, v) => MapEntry(k, (v as num).toInt())),
    );

    // Self-test: tokenize a fixed high-signal SMS, run the real graph.
    // Asserts: all logits finite AND softmax sums to ~1.0.
    const probe =
        'CBI officer speaking. You are under digital arrest. '
        'Do not tell anyone. Call back immediately.';
    final logits = _runInference(interp, tok, probe);

    if (!logits.every((v) => v.isFinite)) {
      interp.close();
      throw MlEngineDeadException(
        'Self-test: non-finite logits $logits — model is corrupt or '
        'input encoding produced NaN; check byte layout',
      );
    }
    final testProbs = _softmax(logits);
    final probSum = testProbs.fold(0.0, (a, b) => a + b);
    if ((probSum - 1.0).abs() > 1e-3) {
      interp.close();
      throw MlEngineDeadException(
        'Self-test: softmax sum $probSum deviates from 1.0 by '
        '${(probSum - 1.0).abs().toStringAsFixed(6)} — model output is invalid',
      );
    }

    _interp = interp;
    _tok = tok;
    _healthy = true;
    _loadError = null;
    debugPrint('[ML] loadModel OK  asset=$asset  probe_probs=$testProbs');
  }

  // Backward-compat wrapper: swallows errors into loadError instead of
  // throwing, so callers that check isReady/loadError rather than try-catching
  // do not need changes.
  Future<void> load({
    String asset = 'assets/ml/defendra_int8.tflite',
  }) async {
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
  // classify
  // ---------------------------------------------------------------------------

  Future<ClassificationResult> classify(String text) async {
    final (:reasons, :keys) = RuleMatcher.matchAll(text);
    final signal = keys.isNotEmpty;

    if (!_healthy) {
      // Model unavailable — rule-only: suspicious if any signal fires, else safe.
      // pScam = NaN to make clear this is NOT a model probability.
      return ClassificationResult(
        verdict: signal ? Verdict.suspicious : Verdict.safe,
        pScam: double.nan,
        probs: const [],
        source: VerdictSource.ruleFallback,
        triggers: keys,
        triggerReasons: reasons,
      );
    }

    final logits = _runInference(_interp!, _tok!, text);
    final probs = _softmax(logits);
    final pScam = probs[1] + probs[2] + probs[3];

    // Rule gate — ML verdict requires corroborating rule signal.
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

  Future<ClassificationResult> scan(String text) => classify(text);

  void dispose() {
    _interp?.close();
    _interp = null;
    _tok = null;
    _healthy = false;
  }

  // ---------------------------------------------------------------------------
  // Inference kernel — writes explicit little-endian int64 bytes to each input
  // tensor.  This is the ONLY safe path: any higher-level run() overload that
  // infers the element type from Dart's List<int> will silently coerce to int32,
  // producing garbage logits with no error.
  // ---------------------------------------------------------------------------

  List<double> _runInference(
    Interpreter interp,
    DartTokenizer tok,
    String text,
  ) {
    final tokens = tok.tokenize(text, maxLength: _kSeqLen);
    final ids = tokens['input_ids']!;
    final mask = tokens['attention_mask']!;

    final idBuf = ByteData(_kSeqLen * 8);
    for (int i = 0; i < _kSeqLen; i++) {
      idBuf.setInt64(i * 8, ids[i], Endian.little);
    }
    interp.getInputTensor(0).data = idBuf.buffer.asUint8List();

    final maskBuf = ByteData(_kSeqLen * 8);
    for (int i = 0; i < _kSeqLen; i++) {
      maskBuf.setInt64(i * 8, mask[i], Endian.little);
    }
    interp.getInputTensor(1).data = maskBuf.buffer.asUint8List();

    interp.invoke();

    final raw = interp.getOutputTensor(0).data.buffer.asFloat32List(0, 4);
    return List<double>.unmodifiable(raw.map((v) => v.toDouble()));
  }

  static List<double> _softmax(List<double> logits) {
    final maxVal = logits.reduce(max);
    final exps = logits.map((v) => exp(v - maxVal)).toList(growable: false);
    final sum = exps.fold(0.0, (a, b) => a + b);
    return List<double>.unmodifiable(exps.map((v) => v / sum));
  }
}

// ---------------------------------------------------------------------------
// ScamLabel — enum used by scanner_screen (label.index for AnimatedSwitcher
// key, label == ScamLabel.digitalArrest for haptic, label.labelDisplay, etc.)
// ---------------------------------------------------------------------------

enum ScamLabel { safe, otpKyc, deliveryCourier, digitalArrest }

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
