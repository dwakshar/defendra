import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../data/models/scan_record.dart';
import 'dart_tokenizer.dart';
import 'rule_matcher.dart';

// Model's positional embeddings are baked at [1, 96, 768] — fixed at export
// time. Never call resizeInputTensor; just pad/truncate every input to 96.
// Phase 4 task: re-export at 128 and update this constant.
const int _maxSeqLen = 96;

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
            print(
              '[TFLite-iso] Input[$i]: name=${t.name} shape=${t.shape} type=${t.type}',
            );
          }
          for (int i = 0; i < outs.length; i++) {
            final t = outs[i];
            print(
              '[TFLite-iso] Output[$i]: name=${t.name} shape=${t.shape} type=${t.type}',
            );
          }
        }

        // Pre-allocate reusable tensor buffers (shape [1, _maxSeqLen]).
        final inputTensors = interp.getInputTensors();
        inputBufs = List.generate(
          inputTensors.length,
          (_) => Int32List(_maxSeqLen),
        );
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
        print(
          '[ML-ISO] ids[0..9]=${ids.take(10).toList()}  real_tokens=$realTokens',
        );
        final logits = _inferReuse(
          interp!,
          tokens,
          inputBufs!,
          segmentBuf!,
          outputBuf!,
        );
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        print('INPUT TEXT : "${msg.text}"');
        print('INPUT IDS  : ${ids.sublist(0, min(20, ids.length))} ...');
        print('RAW OUTPUT : $logits');
        print('OUTPUT LEN : ${logits.length}');
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        msg.replyTo.send(logits);
      } catch (e, st) {
        print('[ML-ERR] Isolate inference failed: $e\n$st');
        msg.replyTo.send('infer_error: $e');
      }
    } else if (msg is _IsolateParity) {
      // Tokenizer-only: no inference. Returns trimmed (non-padded) IDs.
      const testStrings = ['Meeting at 5 PM today.', 'Meeting at 5 PM today'];
      final out = <List<int>>[];
      for (final s in testStrings) {
        final tokens = tok!.tokenize(s, maxLength: _maxSeqLen);
        final ids = tokens['input_ids']!;
        final end = ids.lastIndexWhere((id) => id != 0) + 1;
        out.add(ids.sublist(0, end.clamp(1, ids.length)));
      }
      msg.replyTo.send(out);
    } else if (msg == #dispose) {
      interp?.close();
      port.close();
      return;
    }
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

class MlEngine {
  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  // Keys that almost never appear in legitimate SMS and can override the ML
  // verdict on their own.  Broad contextual keys — phone_number,
  // amount_mentioned, bank_impersonation, otp_request, urgency — fire on ~70%
  // of real Indian bank/delivery notifications and must NOT override alone.
  static const _kHighSignalKeys = {
    'digital_arrest', // "CBI officer", "enforcement directorate" — near-zero FP
    'lottery', // "you won", "lucky draw"
    'job_scam', // "work from home ₹X/day via WhatsApp"
    'delivery_fee', // "customs clearance fee", "release package"
  };
  Isolate? _isolate;

  SendPort? _isolatePort;
  bool _ready = false;

  String? _loadError;

  bool get isReady => _ready;

  /// Non-null when load() failed; surface this to the UI instead of crashing.
  String? get loadError => _loadError;

  // Test-only surface -------------------------------------------------------

  @visibleForTesting
  ScanResult buildResultForTest(
    List<double> logits,
    List<String> reasons,
    List<String> keys,
  ) => _buildResult(logits, reasons, keys);

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

  /// Tokenizes two reference strings in the isolate and prints the IDs
  /// alongside the Python reference so parity can be confirmed at startup.
  Future<void> debugTokenizerParity() async {
    if (!_ready) return;
    const pythonRefNoPeriod = [101, 50986, 10160, 126, 46161, 18745, 102];
    try {
      final replyPort = ReceivePort();
      _isolatePort!.send(_IsolateParity(replyPort.sendPort));
      final raw = await replyPort.first;
      replyPort.close();
      final ids = raw as List<dynamic>;
      final withPeriod = List<int>.from(ids[0] as List);
      final noPeriod = List<int>.from(ids[1] as List);
      final match = noPeriod.toString() == pythonRefNoPeriod.toString();
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ TOKENIZER PARITY');
      print('[PARITY] WITH period   : $withPeriod');
      print('[PARITY] WITHOUT period: $noPeriod');
      print('[PARITY] Python ref    : $pythonRefNoPeriod');
      print(
        match
            ? '[PARITY] ✓ MATCH — Dart tokenizer agrees with Python'
            : '[PARITY] ✗ MISMATCH — check cased/uncased, ## prefix, UNK=100',
      );
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    } catch (e) {
      print('[PARITY] ERROR: $e');
    }
  }

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
      _isolatePort!.send(
        _IsolateInit(
          TransferableTypedData.fromList([modelBytes]),
          vocabJson,
          initReply.sendPort,
        ),
      );
      final ack = await initReply.first;
      initReply.close();
      if (ack is! bool) throw StateError('Isolate init failed: $ack');

      _ready = true;
      _loadError = null;
      await debugTokenizerParity();
    } catch (e, st) {
      _ready = false;
      _loadError = e.toString();
      debugPrint('[ML-LOAD-ERR] $e');
      debugPrintStack(label: '[ML-LOAD-ERR]', stackTrace: st);
    }
  }

  /// Async alias for call-sites that previously used the synchronous scan().
  /// The synchronous path is removed — main-thread inference blocked the UI
  /// for 50–200ms per SMS (well over the 16ms frame budget).
  Future<ScanResult> scan(String text) => classify(text);

  @visibleForTesting
  List<double> softmaxForTest(List<double> logits) => _softmax(logits);

  ScanResult _buildResult(
    List<double> logits,
    List<String> reasons,
    List<String> keys,
  ) {
    if (logits.length != ScamLabel.values.length) {
      throw StateError(
        'Unexpected logits length ${logits.length}; '
        'expected ${ScamLabel.values.length}.',
      );
    }

    debugPrint('[ML] raw_output: $logits');

    // BUG FIX 3 — double softmax guard.
    final rawSum = logits.fold(0.0, (a, b) => a + b);
    final alreadyProbs =
        logits.every((v) => v >= -1e-4) && (rawSum - 1.0).abs() < 1e-2;
    final probs = alreadyProbs ? logits : _softmax(logits);
    debugPrint(
      '[ML] probs(${alreadyProbs ? "passthru" : "softmax"}): '
      '${probs.map((p) => p.toStringAsFixed(3)).toList()}',
    );

    // id2label: 0=safe, 1=otp_kyc, 2=delivery_courier, 3=digital_arrest.
    // Indices 1–3 are scam *categories*, not severity levels.
    final pSafe = probs[0];
    final pScamTotal = probs[1] + probs[2] + probs[3];

    // Argmax over {1,2,3} → which scam category the model predicts.
    int scamIdx = 1;
    for (int i = 2; i <= 3; i++) {
      if (probs[i] > probs[scamIdx]) scamIdx = i;
    }
    final scamCategory = ScamLabel.values[scamIdx];

    debugPrint(
      '[ML] pSafe=${pSafe.toStringAsFixed(3)} '
      'pScamTotal=${pScamTotal.toStringAsFixed(3)} '
      'scamCategory=${scamCategory.categoryId}',
    );

    // Rule-matcher gate: ML verdict must be corroborated by ≥1 rule signal.
    // Without signals a benign message (e.g. "Meeting at 5 PM today") whose
    // softmax happens to peak on otp_kyc must never show as SCAM.
    final hasSignals = keys.isNotEmpty;
    final hasHighSignal = keys.any(_kHighSignalKeys.contains);

    ScamLabel label;
    Verdict verdict;
    var ruleOverride = false;

    if (pScamTotal > 0.85 && hasSignals) {
      label = scamCategory;
      verdict = Verdict.scam;
    } else if (pScamTotal > 0.50 && hasSignals) {
      label = scamCategory;
      verdict = Verdict.suspicious;
    } else if (pScamTotal > 0.50) {
      // ML suspects scam but zero rule signals — cap at SAFE.
      label = ScamLabel.safe;
      verdict = Verdict.safe;
      ruleOverride = true;
    } else {
      label = ScamLabel.safe;
      verdict = Verdict.safe;
    }

    // Near-zero-FP high-signal rules can upgrade an uncertain verdict to
    // SUSPICIOUS (never SCAM) when the ML is ambiguous (pSafe < 0.75).
    if (hasHighSignal && verdict == Verdict.safe && pSafe < 0.75) {
      label = scamCategory;
      verdict = Verdict.suspicious;
      ruleOverride = true;
    }

    // ML argmax only knows 3 categories — rule signals are more accurate for
    // category assignment, so prefer them over the ML's category output.
    final category = verdict == Verdict.safe
        ? 'safe'
        : _categoryFromSignals(keys, scamCategory);

    return ScanResult(
      label: label,
      verdict: verdict,
      confidence: verdict == Verdict.safe ? pSafe : pScamTotal,
      category: category,
      triggerPhrases: reasons,
      firedSignalKeys: keys,
      ruleOverride: ruleOverride,
    );
  }

  ScanResult _fallback(
    List<String> reasons,
    List<String> keys, {
    bool isError = false,
  }) {
    // When the ML model is unavailable, only act on high-signal rules.
    // Broad rules alone (phone number, amount, bank name) must not flag
    // legitimate notifications as scam.
    final hasHighSignal = keys.any(_kHighSignalKeys.contains);
    if (hasHighSignal) {
      return ScanResult(
        label: ScamLabel.otpKyc,
        verdict: Verdict.suspicious,
        confidence: 0.75,
        category: ScamLabel.otpKyc.categoryId,
        triggerPhrases: reasons,
        firedSignalKeys: keys,
        ruleOverride: true,
        isError: isError,
      );
    }
    return ScanResult(
      label: ScamLabel.safe,
      verdict: Verdict.safe,
      confidence: 0.0,
      category: 'none',
      triggerPhrases: reasons,
      firedSignalKeys: keys,
      ruleOverride: true,
      isError: isError,
    );
  }

  // Rule signals are more specific than the ML's 3-class category output.
  // Priority: high-specificity rules first, ML argmax as last resort.
  static String _categoryFromSignals(List<String> keys, ScamLabel mlCategory) {
    if (keys.contains('digital_arrest')) return 'digital_arrest';
    if (keys.contains('delivery_fee')) return 'delivery';
    if (keys.contains('lottery')) return 'lottery';
    if (keys.contains('job_scam')) return 'job';
    if (keys.contains('kyc_fraud') || keys.contains('bank_impersonation')) return 'kyc';
    if (keys.contains('otp_request')) return 'otp';
    return switch (mlCategory) {
      ScamLabel.deliveryCourier => 'delivery',
      ScamLabel.digitalArrest  => 'digital_arrest',
      _                        => 'kyc',
    };
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
  final Verdict verdict;
  final double confidence; // = p_scam_total (probs[1]+probs[2]+probs[3])
  final String category; // snake_case scam type id, or 'none'
  final List<String> triggerPhrases;
  final List<String> firedSignalKeys;
  final bool ruleOverride;
  final bool isError;

  const ScanResult({
    required this.label,
    required this.confidence,
    required this.triggerPhrases,
    this.verdict = Verdict.safe,
    this.category = 'none',
    this.firedSignalKeys = const [],
    this.ruleOverride = false,
    this.isError = false,
  });
}

class _IsolateInfer {
  final String text;
  final SendPort replyTo;
  const _IsolateInfer(this.text, this.replyTo);
}

// ---------------------------------------------------------------------------
// Persistent-isolate protocol — all types must be top-level for Isolate.spawn.
// ---------------------------------------------------------------------------

class _IsolateInit {
  final TransferableTypedData modelBytes;
  final String vocabJson;
  final SendPort replyTo;
  const _IsolateInit(this.modelBytes, this.vocabJson, this.replyTo);
}

class _IsolateParity {
  final SendPort replyTo;
  const _IsolateParity(this.replyTo);
}

extension ScamLabelExt on ScamLabel {
  String get categoryId {
    switch (this) {
      case ScamLabel.safe:
        return 'none';
      case ScamLabel.otpKyc:
        return 'otp_kyc';
      case ScamLabel.deliveryCourier:
        return 'delivery_courier';
      case ScamLabel.digitalArrest:
        return 'digital_arrest';
    }
  }

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
