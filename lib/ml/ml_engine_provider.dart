import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_litert/flutter_litert.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'dart_tokenizer.dart';
import 'ml_engine.dart';

// ---------------------------------------------------------------------------
// Background-isolate worker — dtype checks ONLY, then CLOSE immediately.
//
// The C API (flutter_litert) auto-applies the built-in XNNPACK delegate during
// TfLiteInterpreterCreate → allocateTensors().  XNNPACK claims the float32
// embedding-lookup op, copies its 91 MB weight table internally, then sets
// tensor 120's data.raw = nullptr.  Every subsequent invoke() throws "Input
// tensor 120 lacks data".
//
// The fix: actual inference runs through the Kotlin method channel which uses
// the Java com.google.ai.edge.litert.Interpreter API.  That API does NOT
// auto-apply XNNPACK — it creates a bare CPU interpreter.
//
// This isolate only runs dtype assertions (no invoke) to validate the model
// was not truncated or mis-exported, then closes immediately.
// ---------------------------------------------------------------------------

void _verifyInIsolate(TransferableTypedData ttd) {
  final bytes = ttd.materialize().asUint8List();
  final options = InterpreterOptions();
  final interp = Interpreter.fromBuffer(bytes, options: options);

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

  assertType('input[0]', interp.getInputTensor(0).type, TensorType.int64);
  assertType('input[1]', interp.getInputTensor(1).type, TensorType.int64);
  assertType('output[0]', interp.getOutputTensor(0).type, TensorType.float32);

  debugPrint('[ML-VERIFY] dtype checks OK — input[0,1]=int64 output=float32');
  interp.close();
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

bool _int64ListEq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

const _mlChannel = MethodChannel('com.defendra/ml');

/// Loads, verifies, and exposes the LiteRT engine.
///
/// dtype assertions run in a background Dart isolate (flutter_litert C API,
/// no invoke).  Actual inference is delegated to the Kotlin method channel
/// which uses the Java Interpreter API — bypassing C API auto-XNNPACK.
///
/// On failure, propagates AsyncError — callers use [mlOfflineProvider] and
/// [mlErrorProvider] to surface the failure banner.
final mlEngineProvider = FutureProvider<MlEngine>((ref) async {
  // rootBundle requires the Flutter engine — must run on the main thread.
  final modelData = await rootBundle.load('assets/ml/defendra_int8.tflite');
  final assetBytes = modelData.buffer.asUint8List();
  final vocabJson = await rootBundle.loadString('assets/ml/vocab.json');

  // STARTUP GUARD A — verify the asset was not compressed/truncated by aapt.
  const kMinModelBytes = 100000000; // 100 MB floor
  debugPrint('[ML-VERIFY] model bytes = ${assetBytes.length}');
  if (assetBytes.length < kMinModelBytes) {
    throw MlEngineDeadException(
      'Model asset is only ${assetBytes.length} bytes — expected ~137 MB. '
      'Likely cause: tflite was gzip-compressed by aapt. '
      'Add aaptOptions { noCompress("tflite") } in build.gradle and rebuild.',
    );
  }

  // Verify off the UI thread: dtype checks only (no invoke).
  final ttd = TransferableTypedData.fromList([assetBytes]);
  await Isolate.run(() => _verifyInIsolate(ttd));

  // Copy the asset to a file so Kotlin can load it via File(path).
  final supportDir = await getApplicationSupportDirectory();
  final modelFile = File('${supportDir.path}/defendra_int8.tflite');
  final alreadyCopied =
      await modelFile.exists() &&
      (await modelFile.length()) == assetBytes.length;
  if (!alreadyCopied) {
    await modelFile.writeAsBytes(assetBytes, flush: true);
  }

  // Load the model on the Kotlin/Java side (no XNNPACK auto-apply).
  try {
    await _mlChannel.invokeMethod<void>('loadModel', modelFile.path);
    debugPrint('[ML-VERIFY] Java interpreter loaded — CPU-only, no XNNPACK');
  } on PlatformException catch (e) {
    throw MlEngineDeadException('Java loadModel failed: ${e.message}');
  }

  // STARTUP GUARD B — warmup invoke via Java interpreter.
  try {
    final warmupIds  = Int64List(96);
    final warmupMask = Int64List(96);
    final result = await _mlChannel.invokeListMethod<double>('infer', {
      'ids': warmupIds,
      'mask': warmupMask,
    });
    if (result == null || result.length != 4) {
      throw MlEngineDeadException(
        'Warmup returned unexpected result: $result',
      );
    }
    debugPrint('[ML-VERIFY] warmup invoke OK — logits: $result');
  } on PlatformException catch (e) {
    throw MlEngineDeadException('Warmup invoke failed: ${e.message}');
  }

  final parsed = json.decode(vocabJson) as Map<String, dynamic>;
  final tok = DartTokenizer.fromVocab(
    parsed.map((k, v) => MapEntry(k, (v as num).toInt())),
  );

  // TOKENIZER PARITY — assert first-8 IDs match exactly; abort if not.
  const parityProbes = {
    'KYC update karein': [101, 148, 14703, 10858, 35896, 25085, 17892, 102],
    'Your OTP is 482910': [101, 13554, 152, 36966, 10124, 46810, 74178, 10929],
    'account blocked': [101, 23200, 98935, 102, 0, 0, 0, 0],
  };
  for (final entry in parityProbes.entries) {
    final ids = tok.tokenize(entry.key, maxLength: 96)['input_ids']!;
    final got = ids.take(8).toList();
    debugPrint('[ML-PARITY] "${entry.key}" → $got');
    if (!_int64ListEq(got, entry.value)) {
      await _mlChannel.invokeMethod<void>('close');
      throw MlEngineDeadException(
        'Tokenizer parity FAIL for "${entry.key}": '
        'got $got, expected ${entry.value} — '
        'wrong vocab or do_lower_case=true; fix the tokenizer config.',
      );
    }
  }
  debugPrint('[ML-PARITY] all 3 parity probes OK');

  final engine = MlEngine.loaded(tok);
  ref.onDispose(() async {
    engine.dispose();
    await _mlChannel.invokeMethod<void>('close');
  });
  return engine;
});

/// True only when the engine has permanently failed (unhealthy after load).
final mlOfflineProvider = Provider<bool>((ref) {
  return ref.watch(mlEngineProvider).when(
    data: (engine) => !engine.isReady,
    loading: () => false,
    error: (_, _) => true,
  );
});

/// The error message from the last failed engine load, or null if healthy.
final mlErrorProvider = Provider<String?>((ref) {
  return ref.watch(mlEngineProvider).when(
    data: (engine) => engine.loadError,
    loading: () => null,
    error: (e, _) => e.toString(),
  );
});

/// True while the engine is still initialising (not yet data or error).
final mlLoadingProvider = Provider<bool>((ref) {
  return ref.watch(mlEngineProvider).isLoading;
});
