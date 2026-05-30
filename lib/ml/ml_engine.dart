import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'dart_tokenizer.dart';
import 'rule_matcher.dart';

// Model's positional embeddings are baked at [1, 96, 768] — fixed at export
// time. Never call resizeInputTensor; just pad/truncate every input to 96.
// Phase 4 task: re-export at 128 and update this constant.
const int _maxSeqLen = 96;

// ---------------------------------------------------------------------------
// Persistent-isolate protocol — all types must be top-level for Isolate.spawn.
// ---------------------------------------------------------------------------

class _IsolateInit {
  final TransferableTypedData modelBytes;
  final String vocabJson;
  final SendPort replyTo;
  const _IsolateInit(this.modelBytes, this.vocabJson, this.replyTo);
}

class _IsolateInfer {
  final String text;
  final SendPort replyTo;
  const _IsolateInfer(this.text, this.replyTo);
}

// ---------------------------------------------------------------------------
// Persistent isolate entry — interpreter and tokenizer created once,
// reused for every inference.  Receives only the text string per call
// (not model bytes), eliminating the dominant per-call serialization cost.
// ---------------------------------------------------------------------------

Future<void> _isolateEntry(SendPort toMain) async {
  final port = ReceivePort();
  toMain.send(port.sendPort); // handshake: give main our receive end

  Interpreter? interp;
  DartTokenizer? tok;
  // Pre-allocated tensor buffers — reused every inference to avoid GC pressure.
  List<Int32List>? inputBufs;
  Int32List? segmentBuf; // all-zeros, never mutated
  List<List<double>>? outputBuf;
  bool tensorLogged = false;

  await for (final msg in port) {
    if (msg is _IsolateInit) {
      try {
        final bytes = msg.modelBytes.materialize().asUint8List();
        interp = Interpreter.fromBuffer(bytes);
        interp.allocateTensors();

        if (!tensorLogged) {
          tensorLogged = true;
          final ins = interp.getInputTensors();
          final outs = interp.getOutputTensors();
          for (int i = 0; i < ins.length; i++) {
            final t = ins[i];
            print('[TFLite-iso] Input[$i]: name=${t.name} shape=${t.shape} type=${t.type}');
          }
          for (int i = 0; i < outs.length; i++) {
            final t = outs[i];
            print('[TFLite-iso] Output[$i]: name=${t.name} shape=${t.shape} type=${t.type}');
          }
        }

        // Pre-allocate reusable tensor buffers (shape [1, _maxSeqLen]).
        final inputTensors = interp.getInputTensors();
        inputBufs = List.generate(inputTensors.length, (_) => Int32List(_maxSeqLen));
        segmentBuf = Int32List(_maxSeqLen); // zeros; segment IDs never change
        outputBuf = [List<double>.filled(ScamLabel.values.length, 0.0)];

        final parsed = json.decode(msg.vocabJson) as Map<String, dynamic>;
        tok = DartTokenizer.fromVocab(
          parsed.map((k, v) => MapEntry(k, (v as num).toInt())),
        );

        msg.replyTo.send(true);
      } catch (e) {
        msg.replyTo.send('init_error: $e');
      }
    } else if (msg is _IsolateInfer) {
      try {
        final tokens = tok!.tokenize(msg.text, maxLength: _maxSeqLen);
        final ids = tokens['input_ids']!;
        final realTokens = tokens['attention_mask']!.fold(0, (a, b) => a + b);
        print('[ML-ISO] ids[0..9]=${ids.take(10).toList()}  real_tokens=$realTokens');
        final logits = _inferReuse(interp!, tokens, inputBufs!, segmentBuf!, outputBuf!);
        msg.replyTo.send(logits);
      } catch (e, st) {
        print('[ML-ERR] Isolate inference failed: $e\n$st');
        msg.replyTo.send('infer_error: $e');
      }
    } else if (msg == #dispose) {
      interp?.close();
      port.close();
      return;
    }
  }
}

// ---------------------------------------------------------------------------
// Shared inference kernel using pre-allocated, reusable buffers.
// ---------------------------------------------------------------------------

List<double> _inferReuse(
  Interpreter interp,
  Map<String, List<int>> tokens,
  List<Int32List> inputBufs,
  Int32List segmentBuf,
  List<List<double>> outputBuf,
) {
  final inputTensors = interp.getInputTensors();
  final inputs = <Object>[];

  for (int i = 0; i < inputTensors.length; i++) {
    final name = inputTensors[i].name.toLowerCase();
    if (name.contains('token_type') || name.contains('segment')) {
      // Segment IDs are always zeros for single-sentence input; pre-zeroed.
      inputs.add([segmentBuf]);
    } else if (name.contains('attention') || name.contains('mask')) {
      // BUG FIX 1 — name-based routing avoids feeding wrong tensor slot.
      inputBufs[i].setAll(0, tokens['attention_mask']!);
      inputs.add([inputBufs[i]]);
    } else {
      // input_ids / input_word_ids / unnamed single input.
      // BUG FIX 2 — Int32List forces 32-bit packing; List<int> is 64-bit.
      inputBufs[i].setAll(0, tokens['input_ids']!);
      inputs.add([inputBufs[i]]);
    }
  }

  // Zero output buffer before reuse to avoid stale values from prior inference.
  final buf = outputBuf[0];
  for (int j = 0; j < buf.length; j++) buf[j] = 0.0;

  if (inputs.length > 1) {
    interp.runForMultipleInputs(inputs, {0: outputBuf});
  } else {
    interp.run(inputs[0], outputBuf);
  }

  return List<double>.from(outputBuf[0]);
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

class MlEngine {
  Isolate? _isolate;
  SendPort? _isolatePort;

  bool _ready = false;
  bool get isReady => _ready;

  String? _loadError;

  /// Non-null when load() failed; surface this to the UI instead of crashing.
  String? get loadError => _loadError;

  /// Async inference via the persistent background isolate.
  /// Sends only [text] (~100–500 chars) per call — model bytes are never
  /// re-serialized after the one-time init.
  Future<ScanResult> classify(String text) async {
    final (:reasons, :keys) = RuleMatcher.matchAll(text);
    if (!_ready) return _fallback(reasons, keys, isError: true);

    try {
      final replyPort = ReceivePort();
      _isolatePort!.send(_IsolateInfer(text, replyPort.sendPort));
      final result = await replyPort.first;
      replyPort.close();
      if (result is String) throw StateError(result);
      final logits = result as List<double>;
      debugPrint('[LOGITS-classify] $logits');
      return _buildResult(logits, reasons, keys);
    } catch (e, st) {
      debugPrint('[ML-ERR] classify failed (textLen=${text.length}): $e');
      debugPrintStack(label: '[ML-ERR]', stackTrace: st);
      return _fallback(reasons, keys, isError: true);
    }
  }

  /// Async alias for call-sites that previously used the synchronous scan().
  /// The synchronous path is removed — main-thread inference blocked the UI
  /// for 50–200ms per SMS (well over the 16ms frame budget).
  Future<ScanResult> scan(String text) => classify(text);

  void dispose() {
    _isolatePort?.send(#dispose);
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _isolate = null;
    _isolatePort = null;
    _ready = false;
  }

  /// Spawns the persistent inference isolate and transfers model bytes once
  /// (zero-copy via TransferableTypedData).  Subsequent classify() calls send
  /// only the text string.
  Future<void> load() async {
    try {
      final byteData = await rootBundle.load('assets/ml/model.tflite');
      // Local variable — transferred to isolate; not kept on main heap.
      final modelBytes = byteData.buffer.asUint8List();
      final vocabJson = await rootBundle.loadString('assets/ml/vocab.json');

      final handshake = ReceivePort();
      _isolate = await Isolate.spawn(_isolateEntry, handshake.sendPort);
      _isolatePort = await handshake.first as SendPort;
      handshake.close();

      final initReply = ReceivePort();
      _isolatePort!.send(_IsolateInit(
        TransferableTypedData.fromList([modelBytes]),
        vocabJson,
        initReply.sendPort,
      ));
      final ack = await initReply.first;
      initReply.close();
      if (ack is! bool) throw StateError('Isolate init failed: $ack');

      _ready = true;
      _loadError = null;
    } catch (e, st) {
      _ready = false;
      _loadError = e.toString();
      debugPrint('[ML-LOAD-ERR] $e');
      debugPrintStack(label: '[ML-LOAD-ERR]', stackTrace: st);
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  // Keys that almost never appear in legitimate SMS and can override the ML
  // verdict on their own.  Broad contextual keys — phone_number,
  // amount_mentioned, bank_impersonation, otp_request, urgency — fire on ~70%
  // of real Indian bank/delivery notifications and must NOT override alone.
  static const _kHighSignalKeys = {
    'digital_arrest', // "CBI officer", "enforcement directorate" — near-zero FP
    'lottery',        // "you won", "lucky draw"
    'job_scam',       // "work from home ₹X/day via WhatsApp"
    'delivery_fee',   // "customs clearance fee", "release package"
  };

  ScanResult _buildResult(List<double> logits, List<String> reasons, List<String> keys) {
    if (logits.length != ScamLabel.values.length) {
      throw StateError(
        'Unexpected logits length ${logits.length}; '
        'expected ${ScamLabel.values.length}.',
      );
    }

    debugPrint('[ML] raw_output: $logits');

    // BUG FIX 3 — double softmax guard.
    // Some TFLite exports bake softmax into the final layer (output values are
    // already probabilities summing to ≈1.0).  Applying softmax again collapses
    // every class toward 0.25, destroying confidence.
    final rawSum = logits.fold(0.0, (a, b) => a + b);
    final alreadyProbs =
        logits.every((v) => v >= -1e-4) && (rawSum - 1.0).abs() < 1e-2;
    final probs = alreadyProbs ? logits : _softmax(logits);
    debugPrint('[ML] probs(${alreadyProbs ? "passthru" : "softmax"}): '
        '${probs.map((p) => p.toStringAsFixed(3)).toList()}');

    int maxIdx = 0;
    for (int i = 1; i < probs.length; i++) {
      if (probs[i] > probs[maxIdx]) maxIdx = i;
    }

    var label = ScamLabel.values[maxIdx];
    var confidence = probs[maxIdx];
    var ruleOverride = false;

    // Only override the ML verdict when a high-signal rule fires — not broad
    // contextual rules that match legitimate bank/OTP/delivery notifications.
    final hasHighSignal = keys.any(_kHighSignalKeys.contains);
    if (hasHighSignal && label == ScamLabel.safe && confidence < 0.75) {
      label = ScamLabel.otpKyc;
      confidence = 0.75;
      ruleOverride = true;
    }

    return ScanResult(
      label: label,
      confidence: confidence,
      triggerPhrases: reasons,
      firedSignalKeys: keys,
      ruleOverride: ruleOverride,
    );
  }

  ScanResult _fallback(List<String> reasons, List<String> keys, {bool isError = false}) {
    // When the ML model is unavailable, only act on high-signal rules.
    // Broad rules alone (phone number, amount, bank name) must not flag
    // legitimate notifications as scam.
    final hasHighSignal = keys.any(_kHighSignalKeys.contains);
    if (hasHighSignal) {
      return ScanResult(
        label: ScamLabel.otpKyc,
        confidence: 0.75,
        triggerPhrases: reasons,
        firedSignalKeys: keys,
        ruleOverride: true,
        isError: isError,
      );
    }
    return ScanResult(
      label: ScamLabel.safe,
      confidence: 0.0,
      triggerPhrases: reasons,
      firedSignalKeys: keys,
      ruleOverride: true,
      isError: isError,
    );
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
  final List<String> firedSignalKeys;
  final bool ruleOverride;
  final bool isError;

  const ScanResult({
    required this.label,
    required this.confidence,
    required this.triggerPhrases,
    this.firedSignalKeys = const [],
    this.ruleOverride = false,
    this.isError = false,
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
