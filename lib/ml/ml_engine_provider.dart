import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_litert/flutter_litert.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart_tokenizer.dart';
import 'ml_engine.dart';

// ---------------------------------------------------------------------------
// Shared engine provider — built once, shared by InboxNotifier + ScannerNotifier.
//
// loadModel + allocateTensors runs in a background Dart isolate so the UI
// thread is never blocked during the 200–800 ms graph-build phase.
// The background isolate returns the native TfLiteInterpreter address; the
// main isolate wraps it with Interpreter.fromAddress (zero-cost, instant).
//
// If _buildAndVerify throws (dtype mismatch, non-finite self-test, etc.) the
// FutureProvider surfaces AsyncError and [mlOfflineProvider] returns true.
// ---------------------------------------------------------------------------

/// Loads, verifies, and exposes the LiteRT engine.
/// AsyncError is surfaced when [MlEngineDeadException] is thrown.
final mlEngineProvider = FutureProvider<MlEngine>((ref) async {
  // rootBundle requires the Flutter engine — load both assets on the UI thread.
  final modelData = await rootBundle.load('assets/ml/defendra_int8.tflite');
  final vocabJson = await rootBundle.loadString('assets/ml/vocab_pruned.json');

  // Zero-copy transfer of the 135 MB model bytes to the background isolate.
  final ttd = TransferableTypedData.fromList([modelData.buffer.asUint8List()]);

  // All heavy work — Interpreter.fromBuffer (allocates graph), dtype assertion,
  // XNNPACK warmup invoke — runs off the UI thread.
  final interpAddress = await Isolate.run<int>(
    () => _buildAndVerify(ttd, vocabJson),
  );

  // Reconstruct the interpreter from the native address.  The background
  // isolate exited without calling close(), so the C-level TfLiteInterpreter
  // is still alive — main isolate takes ownership here.
  final interp = Interpreter.fromAddress(interpAddress, allocated: true);

  final parsed = json.decode(vocabJson) as Map<String, dynamic>;
  final tok = DartTokenizer.fromVocab(
    parsed.map((k, v) => MapEntry(k, (v as num).toInt())),
  );

  final engine = MlEngine.loaded(interp, tok);
  ref.onDispose(engine.dispose);
  return engine;
});

/// True when ML verdicts are unavailable: provider loading, errored, or
/// engine unhealthy.  Drives the "ML engine offline" banner in InboxScreen.
final mlOfflineProvider = Provider<bool>((ref) {
  return ref.watch(mlEngineProvider).when(
    data: (engine) => !engine.isReady,
    loading: () => true,
    error: (_, _) => true,
  );
});

// ---------------------------------------------------------------------------
// Background-isolate loader.
// No Flutter engine present — rootBundle cannot be called here.
// The TransferableTypedData and vocabJson string are sent from the main isolate.
// On success, returns the native interpreter address without closing the
// interpreter (ownership transferred to main isolate via fromAddress).
// On failure, throws — Isolate.run propagates this as an error to the caller.
// ---------------------------------------------------------------------------

int _buildAndVerify(TransferableTypedData ttd, String vocabJson) {
  final bytes = ttd.materialize().asUint8List();

  // fromBuffer → _create → Interpreter._(skipAllocate:false) → allocateTensors.
  final interp = Interpreter.fromBuffer(bytes);

  // CPU / XNNPACK only.  GPU delegate is intentionally absent: this model has
  // GATHER_ND and INT64 inputs, both of which the LiteRT GPU delegate rejects.

  void assertType(String label, TensorType actual, TensorType expected) {
    if (actual != expected) {
      interp.close();
      throw MlEngineDeadException(
        '$label dtype: expected $expected, got $actual — '
        'int32-fed-as-int64 bug or wrong model export; '
        'fix the export, do not work around this assertion',
      );
    }
  }

  assertType('input[0]', interp.getInputTensor(0).type, TensorType.int64);
  assertType('input[1]', interp.getInputTensor(1).type, TensorType.int64);
  assertType('output[0]', interp.getOutputTensor(0).type, TensorType.float32);

  // Build tokenizer in-isolate for the self-test (vocab passed as string,
  // no rootBundle needed).
  final parsed = json.decode(vocabJson) as Map<String, dynamic>;
  final tok = DartTokenizer.fromVocab(
    parsed.map((k, v) => MapEntry(k, (v as num).toInt())),
  );

  // Self-test: tokenize a fixed high-signal SMS, invoke the real graph,
  // assert finite logits AND softmax sum ~1.0.
  const seqLen = 96;
  const probe =
      'CBI officer speaking. You are under digital arrest. '
      'Do not tell anyone. Call back immediately.';

  final tokens = tok.tokenize(probe, maxLength: seqLen);
  final ids = tokens['input_ids']!;
  final mask = tokens['attention_mask']!;

  final idBuf = ByteData(seqLen * 8);
  for (var i = 0; i < seqLen; i++) {
    idBuf.setInt64(i * 8, ids[i], Endian.little);
  }
  interp.getInputTensor(0).data = idBuf.buffer.asUint8List();

  final maskBuf = ByteData(seqLen * 8);
  for (var i = 0; i < seqLen; i++) {
    maskBuf.setInt64(i * 8, mask[i], Endian.little);
  }
  interp.getInputTensor(1).data = maskBuf.buffer.asUint8List();

  interp.invoke();

  final raw = interp.getOutputTensor(0).data.buffer.asFloat32List(0, 4);
  final logits = raw.map((v) => v.toDouble()).toList(growable: false);

  if (!logits.every((v) => v.isFinite)) {
    interp.close();
    throw MlEngineDeadException(
      'Self-test: non-finite logits $logits — '
      'model may be corrupt or int64 encoding produced NaN',
    );
  }

  final maxV = logits.reduce(max);
  final exps = logits.map((v) => exp(v - maxV)).toList(growable: false);
  final s = exps.fold(0.0, (a, b) => a + b);
  final probs = exps.map((v) => v / s).toList(growable: false);
  final probSum = probs.fold(0.0, (a, b) => a + b);

  if ((probSum - 1.0).abs() > 1e-3) {
    interp.close();
    throw MlEngineDeadException(
      'Self-test: softmax sum $probSum deviates from 1.0',
    );
  }

  // Return address WITHOUT closing — main isolate owns the interpreter.
  return interp.address;
}
