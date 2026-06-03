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

// Returns (logits, infer_only_us) where infer_only_us covers ONLY the
// interpreter.run call — buffer-fill and output-copy are excluded.
//
// Input arity is hard-wired to 2: [input_ids, attention_mask] in that order,
// matching the model's declared tensor order confirmed by the runtime log
// ("inputTensors.length=2"). We do NOT loop over getInputTensors() here —
// doing so caused a 3rd element to be added when the graph exposes a
// segment/token_type tensor, producing "Input tensor 2 lacks data" at invoke.
(List<double>, int) _inferReuse(
  Interpreter interp,
  Map<String, List<int>> tokens,
  List<Int64List> inputBufs,
  List<List<double>> outputBuf,
) {
  // Fill the two declared input buffers in model-declared order.
  inputBufs[0].setAll(0, tokens['input_ids']!); // tensor 0: input_ids
  inputBufs[1].setAll(0, tokens['attention_mask']!); // tensor 1: attention_mask

  // Zero output buffer before reuse to avoid stale values from prior inference.
  final buf = outputBuf[0];
  for (int j = 0; j < buf.length; j++) buf[j] = 0.0;

  // Exactly 2 inputs — always runForMultipleInputs, never the single-input path.
  final t0 = DateTime.now().microsecondsSinceEpoch;
  interp.runForMultipleInputs([inputBufs[0], inputBufs[1]], {0: outputBuf});
  final inferUs = DateTime.now().microsecondsSinceEpoch - t0;

  return (List<double>.from(outputBuf[0]), inferUs);
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
  List<Int64List>? inputBufs; // int64: matches model-declared input dtype
  List<List<double>>? outputBuf;
  bool tensorLogged = false;
  // Infer-only timing for real classify calls (not benchmark).
  final inferOnlyUs = <int>[];

  await for (final msg in port) {
    if (msg is _IsolateInit) {
      try {
        final bytes = msg.modelBytes.materialize().asUint8List();
        print(
          '[ML-ISO-INIT] model bytes in isolate: ${bytes.length} '
          '(${(bytes.length / 1048576).toStringAsFixed(1)} MB)',
        );
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

        // Pre-allocate one Int64List per model-declared input tensor.
        // Model declares int64 for both input_ids and attention_mask.
        // segmentBuf is not allocated — this model has 2 inputs, not 3.
        final inputTensors = interp.getInputTensors();
        print('[TFLite-iso] inputTensors.length=${inputTensors.length}');
        inputBufs = List.generate(
          inputTensors.length,
          (_) => Int64List(_maxSeqLen),
        );
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
        final (logits, inferUs) = _inferReuse(
          interp!,
          tokens,
          inputBufs!,
          outputBuf!,
        );

        // Sanity-check logits before sending — catch silent model errors.
        final hasNaN = logits.any((v) => v.isNaN || v.isInfinite);
        final allZero = logits.every((v) => v == 0.0);
        print(
          '[ML-ISO] logits_sane: hasNaN=$hasNaN  allZero=$allZero  logits=$logits',
        );

        // Track infer-only times and report median every 5 real classifies.
        inferOnlyUs.add(inferUs);
        final n = inferOnlyUs.length;
        final lastMs = (inferUs / 1000).toStringAsFixed(1);
        if (n % 5 == 0) {
          final sorted = [...inferOnlyUs]..sort();
          final medUs = sorted[sorted.length ~/ 2];
          print(
            '[ML-INFER-TIMING] n=$n  '
            'interpreter.run  last=${lastMs}ms  '
            'median=${(medUs / 1000).toStringAsFixed(1)}ms  '
            'p95=${(sorted[(sorted.length * 0.95).floor()] / 1000).toStringAsFixed(1)}ms',
          );
        } else {
          print(
            '[ML-INFER-TIMING] interpreter.run  last=${lastMs}ms  sample=$n/5',
          );
        }

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
    } else if (msg is _IsolateBenchmark) {
      // 100 timed runs at seqlen 96 over all 4 probe texts.
      // Reports: tokenize_us, infer_us, verdict_us (all microseconds), per run.
      final probes = [
        // safe
        'Your SBI balance is Rs 12345 as on 31-May-2026. For queries call 1800.',
        // otp_kyc
        '<name> aapka otp <otp> hai account update ke liye hamare executive ko share karein <phone>',
        // delivery_courier
        'Your parcel is held at customs. Pay Rs 499 clearance fee to release. Click <url>',
        // digital_arrest
        'CBI officer speaking. You are under digital arrest. Do not tell anyone. Call back <phone>.',
      ];

      final tokenizeTimes = <int>[];
      final inferTimes = <int>[];
      final verdictTimes = <int>[];

      for (int run = 0; run < msg.runs; run++) {
        final text = probes[run % probes.length];

        final t0 = DateTime.now().microsecondsSinceEpoch;
        final tokens = tok!.tokenize(text, maxLength: _maxSeqLen);
        final t1 = DateTime.now().microsecondsSinceEpoch;
        final (logits, inferUs) = _inferReuse(
          interp!,
          tokens,
          inputBufs!,
          outputBuf!,
        );
        final t2 = DateTime.now().microsecondsSinceEpoch;

        // Verdict map (softmax + thresholds) — mirrors _buildResult without rule signals.
        final rawSum = logits.fold(0.0, (a, b) => a + b);
        final probs =
            (logits.every((v) => v >= -1e-4) && (rawSum - 1.0).abs() < 1e-2)
            ? logits
            : () {
                final maxV = logits.reduce(max);
                final exps = logits.map((v) => exp(v - maxV)).toList();
                final s = exps.fold(0.0, (a, b) => a + b);
                return exps.map((v) => v / s).toList();
              }();
        // ignore: unused_local_variable
        final pScam = probs[1] + probs[2] + probs[3];
        final t3 = DateTime.now().microsecondsSinceEpoch;

        tokenizeTimes.add(t1 - t0);
        inferTimes.add(
          inferUs,
        ); // infer-only (interpreter.run), not full _inferReuse
        verdictTimes.add(t3 - t2);
      }

      msg.replyTo.send({
        'tokenize_us': tokenizeTimes,
        'infer_us': inferTimes,
        'verdict_us': verdictTimes,
      });
    } else if (msg is _IsolateParity) {
      // Tokenizer-only: no inference. Returns trimmed (non-padded) IDs.
      // String 0: plain sentence — verifies special-token IDs and basic WordPiece.
      // String 1: scam SMS — verifies <url>/<amount>/<otp> substitution + lowercase.
      const testStrings = [
        'Meeting at 5 PM today',
        'Pay Rs 499 clearance fee to release. Click http://bit.ly/xyz your OTP 847291',
      ];
      final t =
          tok!; // non-null local — init must have run before parity is sent
      final sepId = t.vocab['[SEP]'] ?? 3; // pruned vocab: [SEP]=3
      final out = <List<int>>[];
      for (final s in testStrings) {
        final tokens = t.tokenize(s, maxLength: _maxSeqLen);
        final ids = tokens['input_ids']!;
        final end = ids.indexOf(sepId) + 1;
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

class BenchmarkResult {
  final List<int> tokenizeUs;
  final List<int> inferUs;
  final List<int> verdictUs;
  final int? coldStartMs;

  const BenchmarkResult({
    required this.tokenizeUs,
    required this.inferUs,
    required this.verdictUs,
    this.coldStartMs,
  });

  int get totalMedianUs => _median(
    List.generate(
      tokenizeUs.length,
      (i) => tokenizeUs[i] + inferUs[i] + verdictUs[i],
    ),
  );

  int get totalP95Us => _p95(
    List.generate(
      tokenizeUs.length,
      (i) => tokenizeUs[i] + inferUs[i] + verdictUs[i],
    ),
  );

  @override
  String toString() =>
      '''
BenchmarkResult (n=${tokenizeUs.length})
  tokenize  median=${_median(tokenizeUs)}µs  p95=${_p95(tokenizeUs)}µs
  infer     median=${_median(inferUs)}µs  p95=${_p95(inferUs)}µs
  verdict   median=${_median(verdictUs)}µs  p95=${_p95(verdictUs)}µs
  ─────────────────────────────────────────────
  end-to-end  median=$totalMedianUsµs (${(totalMedianUs / 1000).toStringAsFixed(1)}ms)  p95=$totalP95Usµs (${(totalP95Us / 1000).toStringAsFixed(1)}ms)
  cold-start  ${coldStartMs != null ? '$coldStartMs ms' : 'not measured'}''';
  int _median(List<int> v) {
    final s = [...v]..sort();
    return s[s.length ~/ 2];
  }

  int _p95(List<int> v) {
    final s = [...v]..sort();
    return s[(s.length * 0.95).floor()];
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
    'kyc_fraud', // "kyc update", "account block" — high-specificity fraud pattern
    'bank_impersonation', // named bank + account/card action — high-specificity
    'otp_request', // sender asking recipient to share OTP
    'digital_arrest', // "CBI officer", "enforcement directorate" — near-zero FP
    'lottery', // "you won", "lucky draw"
    'job_scam', // "work from home ₹X/day via WhatsApp"
    'delivery_fee', // "customs clearance fee", "release package"
    'advance_fee_recruitment', // "selected + security deposit" — near-zero FP in legit SMS
  };
  Isolate? _isolate;
  ReceivePort? _exitPort;
  ReceivePort? _errorPort;

  SendPort? _isolatePort;
  bool _ready = false;

  String? _loadError;

  int? _coldStartMs;

  /// Wall-clock milliseconds for the last load() call (model read + isolate init).
  int? get coldStartMs => _coldStartMs;

  bool get isReady => _ready;

  /// Non-null when load() failed; surface this to the UI instead of crashing.
  String? get loadError => _loadError;

  /// Runs [runs] classify cycles in the isolate and returns timing statistics.
  /// Each cycle: tokenize → infer → verdict map (softmax + threshold).
  /// Also includes the stored cold-start load time.
  Future<BenchmarkResult> benchmark({int runs = 100}) async {
    if (!_ready) throw StateError('MlEngine not ready; call load() first.');
    final replyPort = ReceivePort();
    _isolatePort!.send(_IsolateBenchmark(runs, replyPort.sendPort));
    final raw = await replyPort.first as Map;
    replyPort.close();

    List<int> us(String key) => List<int>.from(raw[key] as List);
    return BenchmarkResult(
      tokenizeUs: us('tokenize_us'),
      inferUs: us('infer_us'),
      verdictUs: us('verdict_us'),
      coldStartMs: _coldStartMs,
    );
  }

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

    final replyPort = ReceivePort();
    try {
      _isolatePort!.send(_IsolateInfer(text, replyPort.sendPort));
      // 15 s cap — if the isolate crashes at the native level (JNI fault, OOM)
      // it never sends a reply, so without a timeout classify() hangs forever,
      // keeping isLoading:true in the UI and blocking _onSms indefinitely.
      final result = await replyPort.first.timeout(const Duration(seconds: 15));
      if (result is String) throw StateError(result);
      final logits = result as List<double>;
      debugPrint('[LOGITS-classify] $logits');
      return _buildResult(logits, reasons, keys);
    } catch (e, st) {
      debugPrint('[ML-ERR] classify failed (textLen=${text.length}): $e');
      debugPrintStack(label: '[ML-ERR]', stackTrace: st);
      return _fallback(reasons, keys, isError: true);
    } finally {
      replyPort.close();
    }
  }

  /// Tokenizes reference strings in the isolate and compares to Python output.
  ///
  /// References computed with vocab_pruned.json + lowercasing + preprocess:
  ///   python scripts/prune_vocab.py (step5) — see parity strings there.
  Future<void> debugTokenizerParity() async {
    if (!_ready) return;
    // Pruned-vocab IDs for "meeting at 5 pm today" (no period, lowercased).
    // Old mBERT IDs were [101, 50986, 10160, 126, 46161, 18745, 102] — wrong
    // for model_pruned_int8.tflite which uses remapped embedding row indices.
    const pythonRefPlain = [2, 12046, 10049, 27, 14206, 11923, 3];
    // Pruned-vocab IDs for a scam SMS exercising <url>/<amount>/<otp> substitution:
    //   "pay rs 499 clearance fee to release. click http://bit.ly/xyz your otp 847291"
    // After lowercase + preprocess → "pay <amount> clearance fee to release. click <url> your otp <otp>"
    const pythonRefScam = [
      2,
      11652,
      34,
      13645,
      12152,
      15717,
      12579,
      11600,
      14298,
      10015,
      11185,
      20,
      72,
      14669,
      34,
      10255,
      10050,
      15717,
      12122,
      14536,
      10189,
      34,
      10518,
      10189,
      15717,
      3,
    ];
    try {
      final replyPort = ReceivePort();
      _isolatePort!.send(_IsolateParity(replyPort.sendPort));
      final raw = await replyPort.first;
      replyPort.close();
      final ids = raw as List<dynamic>;
      final plainIds = List<int>.from(ids[0] as List);
      final scamIds = List<int>.from(ids[1] as List);
      final plainMatch = plainIds.toString() == pythonRefPlain.toString();
      final scamMatch = scamIds.toString() == pythonRefScam.toString();
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ TOKENIZER PARITY (vocab_pruned)');
      print('[PARITY] plain  Dart: $plainIds');
      print('[PARITY] plain  Py  : $pythonRefPlain');
      print('[PARITY] plain  : ${plainMatch ? "✓ MATCH" : "✗ MISMATCH"}');
      print('[PARITY] scam   Dart: $scamIds');
      print('[PARITY] scam   Py  : $pythonRefScam');
      print(
        '[PARITY] scam   : ${scamMatch ? "✓ MATCH (url+amount+otp substitution confirmed)" : "✗ MISMATCH — check _preprocess lowercasing and placeholder path"}',
      );
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    } catch (e) {
      print('[PARITY] ERROR: $e');
    }
  }

  void dispose() {
    _isolatePort?.send(#dispose);
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _exitPort?.close();
    _errorPort?.close();
    _isolate = null;
    _isolatePort = null;
    _exitPort = null;
    _errorPort = null;
    _ready = false;
  }

  /// Spawns the persistent inference isolate and transfers model bytes once
  /// (zero-copy via TransferableTypedData).  Subsequent classify() calls send
  /// only the text string.
  Future<void> load() async {
    final loadStart = DateTime.now().millisecondsSinceEpoch;
    try {
      const modelAsset = 'assets/ml/model_pruned_int8.tflite';
      final byteData = await rootBundle.load(modelAsset);
      // Local variable — transferred to isolate; not kept on main heap.
      final modelBytes = byteData.buffer.asUint8List();
      debugPrint(
        '[ML-LOAD] asset=$modelAsset  '
        'size=${modelBytes.length} bytes  '
        '(${(modelBytes.length / 1048576).toStringAsFixed(1)} MB)',
      );
      // Must match the model: vocab_pruned.json has remapped IDs (0..24393)
      // that align with the pruned embedding table inside model_pruned_int8.tflite.
      // vocab.json has original mBERT IDs (0..119546) which are WRONG for this model.
      final vocabJson = await rootBundle.loadString(
        'assets/ml/vocab_pruned.json',
      );

      final handshake = ReceivePort();
      _exitPort = ReceivePort();
      _errorPort = ReceivePort();
      _isolate = await Isolate.spawn(
        _isolateEntry,
        handshake.sendPort,
        onExit: _exitPort!.sendPort,
        onError: _errorPort!.sendPort,
      );
      // Detect native isolate crash (JNI fault, OOM) immediately — without this,
      // every classify() would hang until the 15 s timeout instead of falling
      // back to rule-based results right away.
      _exitPort!.listen((_) {
        if (_ready) {
          debugPrint(
            '[ML] Isolate exited unexpectedly — ML disabled, using rule-based fallback',
          );
          _ready = false;
        }
      });
      _errorPort!.listen((err) {
        debugPrint('[ML-ERR] Isolate fatal error: $err');
        _ready = false;
      });
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
      // 20 s cap — if the isolate crashes before responding (native JNI fault,
      // OOM, bad model bytes) the receive future never completes otherwise.
      final ack = await initReply.first.timeout(const Duration(seconds: 20));
      initReply.close();
      if (ack is! bool) throw StateError('Isolate init failed: $ack');

      _ready = true;
      _loadError = null;
      _coldStartMs = DateTime.now().millisecondsSinceEpoch - loadStart;
      await debugTokenizerParity();
      if (kDebugMode) await selfTest();
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

  /// Runs 5 fixed SMS texts through the real classify() path and logs
  /// source, raw logits, and per-inference ms so the input-arity fix can be
  /// confirmed without waiting for real incoming SMS.
  Future<void> selfTest() async {
    if (!_ready) {
      debugPrint('[ML-SELFTEST] skipped — engine not ready');
      return;
    }
    const probes = <(String, String)>[
      (
        'job_scam',
        'Aapka selection ho gaya part-time job ke liye. Rs.2000 daily. Registration fee Rs.450 jama karein confirm karne ke liye.',
      ),
      (
        'otp_kyc',
        'Dear customer, your SBI OTP is 847291. Share with our executive to complete KYC update immediately.',
      ),
      (
        'digital_arrest',
        'CBI officer speaking. You are under digital arrest. Do not tell anyone. Call back immediately.',
      ),
      (
        'safe_bank',
        'Your HDFC Bank account XX1234 is credited Rs.5000.00 on 01-Jun-26. Avl Bal: Rs.23450.00.',
      ),
      (
        'delivery_fee',
        'Your parcel is held at customs. Pay Rs 499 clearance fee to release. Click the link to pay.',
      ),
    ];
    debugPrint('[ML-SELFTEST] ── 5-SMS self-test on real classify() path ──');
    for (final (label, text) in probes) {
      final result = await classify(text);
      debugPrint(
        '[ML-SELFTEST] $label  '
        'source=${result.ruleOverride ? "rule" : "model"}  '
        'verdict=${result.verdict.name}  '
        'conf=${result.confidence.toStringAsFixed(3)}  '
        'keys=${result.firedSignalKeys}',
      );
    }
    debugPrint('[ML-SELFTEST] ── done ──');
  }

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

    debugPrint(
      '[ML-VERDICT] source=${ruleOverride ? "rule_override" : "model"}  '
      'verdict=$verdict  conf=${(verdict == Verdict.safe ? pSafe : pScamTotal).toStringAsFixed(3)}  '
      'pSafe=${pSafe.toStringAsFixed(3)}  pScamTotal=${pScamTotal.toStringAsFixed(3)}  '
      'hasSignals=$hasSignals  hasHighSignal=$hasHighSignal  keys=$keys',
    );

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
    final highCount = keys.where(_kHighSignalKeys.contains).length;
    // confidence sentinels — not model probabilities; log source clearly.
    debugPrint(
      '[ML-VERDICT] source=rule_fallback  isError=$isError  '
      'highCount=$highCount  keys=$keys  '
      'confidence=${highCount >= 2
          ? 0.90
          : highCount == 1
          ? 0.75
          : 0.0} '
      '(sentinel, not model output)',
    );
    if (highCount >= 2) {
      final category = _categoryFromSignals(keys, ScamLabel.otpKyc);
      return ScanResult(
        label: ScamLabel.otpKyc,
        verdict: Verdict.scam,
        confidence: 0.90,
        category: category,
        triggerPhrases: reasons,
        firedSignalKeys: keys,
        ruleOverride: true,
        isError: isError,
      );
    }
    if (highCount == 1) {
      final category = _categoryFromSignals(keys, ScamLabel.otpKyc);
      return ScanResult(
        label: ScamLabel.otpKyc,
        verdict: Verdict.suspicious,
        confidence: 0.75,
        category: category,
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

  List<double> _softmax(List<double> logits) {
    final maxVal = logits.reduce(max);
    final exps = logits.map((v) => exp(v - maxVal)).toList();
    final sum = exps.fold(0.0, (a, b) => a + b);
    return exps.map((v) => v / sum).toList();
  }

  // Rule signals are more specific than the ML's 3-class category output.
  // Priority: high-specificity rules first, ML argmax as last resort.
  static String _categoryFromSignals(List<String> keys, ScamLabel mlCategory) {
    if (keys.contains('digital_arrest')) return 'digital_arrest';
    if (keys.contains('delivery_fee')) return 'delivery';
    if (keys.contains('lottery')) return 'lottery';
    if (keys.contains('job_scam')) return 'job';
    if (keys.contains('kyc_fraud') || keys.contains('bank_impersonation'))
      return 'kyc';
    if (keys.contains('otp_request')) return 'otp';
    return switch (mlCategory) {
      ScamLabel.deliveryCourier => 'delivery',
      ScamLabel.digitalArrest => 'digital_arrest',
      _ => 'kyc',
    };
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

class _IsolateBenchmark {
  final int runs;
  final SendPort replyTo;
  const _IsolateBenchmark(this.runs, this.replyTo);
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
