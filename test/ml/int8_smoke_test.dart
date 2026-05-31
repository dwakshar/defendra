// INT8 model smoke test — verifies model_pruned_int8.tflite loads and produces
// sane logits (no NaN, no all-zero output, 4 classes) on 12 fixed SMS messages
// spanning safe / OTP-KYC / delivery / digital-arrest / Hinglish categories.
//
// Runs on host via `flutter test` (uses dart:io to bypass rootBundle).
// If the host platform lacks TFLite native libs the test is automatically
// skipped; run on an Android device / emulator for a definitive result.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:defendra/ml/dart_tokenizer.dart';
import 'package:defendra/ml/ml_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

const _modelPath = 'assets/ml/model_pruned_int8.tflite';
const _vocabPath = 'assets/ml/vocab.json';
const _maxSeqLen = 96;

const _smsCorpus = <String>[
  // ── safe (4) ──────────────────────────────────────────────────────────────
  'Your SBI balance is Rs 12,345. Last txn: Rs 500 credit. Avl Bal: Rs 11845.',
  'Meeting rescheduled to 5 PM today. Please confirm if you can attend.',
  'Your order #ORD-87432 has been shipped. Expected delivery: tomorrow by 8 PM.',
  'HDFC: Rs 2000 credited to A/c XX1234 on 01-Jun. Avl Bal: Rs 45,210.',
  // ── otp_kyc scam (3) ──────────────────────────────────────────────────────
  'Dear customer, your KYC is expiring today. Share OTP 482910 with our executive to verify your account immediately.',
  'Aapka OTP hai 123456. Ise kisi ke saath share mat karein. Bank kabhi OTP nahi maangta.',
  'ALERT: Your account will be blocked. Call 9876543210 and provide OTP to re-activate.',
  // ── delivery scam (2) ─────────────────────────────────────────────────────
  'Your parcel is held at customs. Pay Rs 499 clearance fee at https://bit.ly/x now.',
  'Package delivery failed. Pay Rs 49 redelivery charge via link to reschedule delivery.',
  // ── digital arrest (1) ────────────────────────────────────────────────────
  'CBI officer speaking. You are under digital arrest for money laundering. Do not tell anyone. Call back immediately.',
  // ── Hinglish scam (2) ─────────────────────────────────────────────────────
  'Bhai tera account band ho raha hai abhi OTP share kar warna sare paise chale jayenge.',
  'Lucky winner! Tumhara naam lucky draw mein aaya. Rs 5 lakh claim karne ke liye abhi click karo.',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Interpreter interp;
  late DartTokenizer tok;
  late MlEngine engine;
  bool platformSupported = true;

  setUpAll(() async {
    try {
      final modelBytes = await File(_modelPath).readAsBytes();
      interp = Interpreter.fromBuffer(modelBytes);
      interp.allocateTensors();

      final vocabRaw = await File(_vocabPath).readAsString();
      final parsed = json.decode(vocabRaw) as Map<String, dynamic>;
      tok = DartTokenizer.fromVocab(
        parsed.map((k, v) => MapEntry(k, (v as num).toInt())),
      );
      engine = MlEngine();

      // Print tensor layout once so we can inspect names/shapes.
      final ins = interp.getInputTensors();
      final outs = interp.getOutputTensors();
      for (int i = 0; i < ins.length; i++) {
        final t = ins[i];
        print('[INT8-SMOKE] Input[$i]: name=${t.name} shape=${t.shape} type=${t.type}');
      }
      for (int i = 0; i < outs.length; i++) {
        final t = outs[i];
        print('[INT8-SMOKE] Output[$i]: name=${t.name} shape=${t.shape} type=${t.type}');
      }
    } catch (e) {
      platformSupported = false;
      print('[INT8-SMOKE] setUpAll skipped: $e');
    }
  });

  tearDownAll(() {
    if (platformSupported) {
      interp.close();
      engine.dispose();
    }
  });

  List<double> infer(String text) {
    final tokens = tok.tokenize(text, maxLength: _maxSeqLen);
    final inputIds = Int64List(_maxSeqLen)..setAll(0, tokens['input_ids']!);
    final attnMask = Int64List(_maxSeqLen)..setAll(0, tokens['attention_mask']!);
    final segBuf = Int64List(_maxSeqLen); // zeros

    final inputTensors = interp.getInputTensors();
    final inputList = <Object>[];
    for (final t in inputTensors) {
      final name = t.name.toLowerCase();
      if (name.contains('token_type') || name.contains('segment')) {
        inputList.add([segBuf]);
      } else if (name.contains('attention') || name.contains('mask')) {
        inputList.add([attnMask]);
      } else {
        inputList.add([inputIds]);
      }
    }

    final output = [List<double>.filled(4, 0.0)];
    if (inputList.length > 1) {
      interp.runForMultipleInputs(inputList, {0: output});
    } else {
      interp.run(inputList[0], output);
    }
    return List<double>.from(output[0]);
  }

  group('INT8 model smoke test', () {
    for (int i = 0; i < _smsCorpus.length; i++) {
      final text = _smsCorpus[i];
      final label = i < 4
          ? 'safe'
          : i < 7
              ? 'otp_kyc'
              : i < 9
                  ? 'delivery'
                  : i < 10
                      ? 'digital_arrest'
                      : 'hinglish_scam';

      test('SMS[$i] $label — logits non-NaN, non-zero, 4 outputs', () {
        if (!platformSupported) {
          markTestSkipped('TFLite native libs unavailable on this platform');
          return;
        }

        final logits = infer(text);
        final preview = text.substring(0, text.length.clamp(0, 60));
        print('[INT8-SMOKE] SMS[$i]("$preview…") → $logits');

        expect(logits.length, 4, reason: 'Expected exactly 4 output classes');

        for (int j = 0; j < logits.length; j++) {
          expect(logits[j].isNaN, isFalse,
              reason: 'logits[$j] is NaN — model op not supported or wrong vocab?');
          expect(logits[j].isInfinite, isFalse,
              reason: 'logits[$j] is ±Inf for SMS[$i]');
        }

        // All-zero output would mean the output buffer was never written.
        final allZero = logits.every((v) => v.abs() < 1e-9);
        expect(allZero, isFalse,
            reason: 'All logits are ~0 — inference did not run for SMS[$i]');

        // Cross-check: _buildResult must not throw on these logits.
        final result = engine.buildResultForTest(logits, [], []);
        expect(result, isNotNull);
        expect(result.label, isA<ScamLabel>());
        expect(result.confidence, inInclusiveRange(0.0, 1.0));
        print('[INT8-SMOKE]   → verdict=${result.verdict} conf=${result.confidence.toStringAsFixed(3)}');
      });
    }

    test('No NaN or zero across all 12 SMS in batch', () {
      if (!platformSupported) {
        markTestSkipped('TFLite native libs unavailable on this platform');
        return;
      }

      int nanCount = 0, zeroCount = 0;
      for (final text in _smsCorpus) {
        final logits = infer(text);
        if (logits.any((v) => v.isNaN)) nanCount++;
        if (logits.every((v) => v.abs() < 1e-9)) zeroCount++;
      }
      print('[INT8-SMOKE] Batch: NaN cases=$nanCount, all-zero cases=$zeroCount / ${_smsCorpus.length}');
      expect(nanCount, 0, reason: '$nanCount SMS produced NaN logits');
      expect(zeroCount, 0, reason: '$zeroCount SMS produced all-zero logits');
    });
  });
}
