// ignore_for_file: avoid_redundant_argument_values

import 'package:defendra/data/models/scan_record.dart';
import 'package:defendra/ml/ml_engine.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// All tests drive MlEngine.buildResultForTest with already-normalised
// probability vectors (sum≈1.0, all ≥ 0).  The double-softmax guard in
// _buildResult treats these as pass-through (no second softmax), so
// pScamTotal = probs[1]+probs[2]+probs[3] exactly.
//
// Rule:
//   pScamTotal > 0.85 && hasSignals      → SCAM
//   pScamTotal > 0.50 && hasSignals      → SUSPICIOUS
//   pScamTotal > 0.50  (no signals)      → SAFE  (ruleOverride=true)
//   else                                 → SAFE
//   hasHighSignal && verdict==SAFE && pSafe < 0.75 → SUSPICIOUS (upgrade)
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // pScamTotal is probs[1]+probs[2]+probs[3]
  // =========================================================================

  group('Verdict mapping — pScamTotal = probs[1]+probs[2]+probs[3]', () {
    late MlEngine engine;
    setUp(() => engine = MlEngine());
    tearDown(() => engine.dispose());

    test('pScamTotal sums indices 1+2+3 (not 0+1+2)', () {
      // probs[0]=0.1 (safe), probs[1]+[2]+[3]=0.9 → SCAM with any signal
      final r = engine.buildResultForTest(
        [0.1, 0.3, 0.3, 0.3],
        ['KYC / account-block urgency'],
        ['kyc_fraud'],
      );
      expect(r.verdict, Verdict.scam);
      // confidence = pScamTotal for non-safe verdicts
      expect(r.confidence, closeTo(0.9, 1e-6));
    });

    test('confidence = pScamTotal when SCAM', () {
      final r = engine.buildResultForTest(
        [0.05, 0.95, 0.0, 0.0],
        ['Lottery / prize scam'],
        ['lottery'],
      );
      expect(r.verdict, Verdict.scam);
      expect(r.confidence, closeTo(0.95, 1e-6));
    });

    test('confidence = pScamTotal when SUSPICIOUS', () {
      final r = engine.buildResultForTest(
        [0.30, 0.70, 0.0, 0.0],
        ['OTP solicitation'],
        ['otp_request'],
      );
      expect(r.verdict, Verdict.suspicious);
      expect(r.confidence, closeTo(0.70, 1e-6));
    });

    test('confidence = pSafe (probs[0]) when SAFE', () {
      final r = engine.buildResultForTest(
        [0.80, 0.10, 0.05, 0.05],
        [],
        [],
      );
      expect(r.verdict, Verdict.safe);
      expect(r.confidence, closeTo(0.80, 1e-6));
    });
  });

  // =========================================================================
  // Boundary values — all four explicit thresholds
  // =========================================================================

  group('Verdict mapping — boundary values', () {
    late MlEngine engine;
    setUp(() => engine = MlEngine());
    tearDown(() => engine.dispose());

    // --- 0.851: just above SCAM threshold ---
    test('pScamTotal=0.851, signal present → SCAM', () {
      final r = engine.buildResultForTest(
        [0.149, 0.851, 0.0, 0.0],
        ['Shortened URL detected'],
        ['shortened_url'],
      );
      expect(r.verdict, Verdict.scam);
      expect(r.confidence, closeTo(0.851, 1e-6));
    });

    // --- 0.849: just below SCAM threshold → SUSPICIOUS ---
    test('pScamTotal=0.849, signal present → SUSPICIOUS (not SCAM)', () {
      final r = engine.buildResultForTest(
        [0.151, 0.849, 0.0, 0.0],
        ['Shortened URL detected'],
        ['shortened_url'],
      );
      expect(r.verdict, Verdict.suspicious);
      expect(r.verdict, isNot(Verdict.scam));
      expect(r.confidence, closeTo(0.849, 1e-6));
    });

    // --- 0.50: boundary — NOT strictly greater than → SAFE ---
    test('pScamTotal=0.50, signal present → SAFE (boundary: 0.50 is NOT > 0.50)', () {
      final r = engine.buildResultForTest(
        [0.50, 0.50, 0.0, 0.0],
        ['Phone number in message body'],
        ['phone_number'],
      );
      expect(r.verdict, Verdict.safe);
      expect(r.verdict, isNot(Verdict.scam));
    });

    // --- 0.499: below SUSPICIOUS threshold → SAFE ---
    test('pScamTotal=0.499, signal present → SAFE', () {
      final r = engine.buildResultForTest(
        [0.501, 0.499, 0.0, 0.0],
        ['Phone number in message body'],
        ['phone_number'],
      );
      expect(r.verdict, Verdict.safe);
    });

    // --- 0.501: just above SUSPICIOUS threshold → SUSPICIOUS ---
    test('pScamTotal=0.501, signal present → SUSPICIOUS', () {
      final r = engine.buildResultForTest(
        [0.499, 0.501, 0.0, 0.0],
        ['Urgency'],
        ['urgency'],
      );
      expect(r.verdict, Verdict.suspicious);
      expect(r.confidence, closeTo(0.501, 1e-6));
    });

    // --- 0.85: at the exact SCAM threshold → SUSPICIOUS (NOT > 0.85) ---
    test('pScamTotal=0.85 exactly, signal present → SUSPICIOUS (not SCAM)', () {
      final r = engine.buildResultForTest(
        [0.15, 0.85, 0.0, 0.0],
        ['Urgency'],
        ['urgency'],
      );
      expect(r.verdict, Verdict.suspicious);
      expect(r.verdict, isNot(Verdict.scam));
    });

    // spread across classes: probs[1]+[2]+[3] tested with multi-class
    test('pScamTotal spread across all three scam classes, signal → uses sum', () {
      // probs[1]=0.30, probs[2]=0.30, probs[3]=0.30 → pScamTotal=0.90 > 0.85
      final r = engine.buildResultForTest(
        [0.10, 0.30, 0.30, 0.30],
        ['Law enforcement impersonation'],
        ['digital_arrest'],
      );
      expect(r.verdict, Verdict.scam);
      expect(r.confidence, closeTo(0.90, 1e-6));
    });
  });

  // =========================================================================
  // NEVER SCAM with zero rule signals
  // =========================================================================

  group('Verdict mapping — NEVER SCAM with zero rule signals', () {
    late MlEngine engine;
    setUp(() => engine = MlEngine());
    tearDown(() => engine.dispose());

    test('pScamTotal=0.851, zero signals → SAFE (not SCAM)', () {
      final r = engine.buildResultForTest(
        [0.149, 0.851, 0.0, 0.0],
        [],
        [],
      );
      expect(r.verdict, Verdict.safe);
      expect(r.verdict, isNot(Verdict.scam));
      expect(r.ruleOverride, isTrue);
    });

    test('pScamTotal=0.99, zero signals → SAFE (not SCAM)', () {
      final r = engine.buildResultForTest(
        [0.01, 0.99, 0.0, 0.0],
        [],
        [],
      );
      expect(r.verdict, Verdict.safe);
      expect(r.verdict, isNot(Verdict.scam));
    });

    test('pScamTotal=1.0 (degenerate), zero signals → SAFE', () {
      final r = engine.buildResultForTest(
        [0.0, 1.0, 0.0, 0.0],
        [],
        [],
      );
      expect(r.verdict, Verdict.safe);
    });

    test('multiple pScamTotal values, all with zero signals → never SCAM', () {
      for (final pScam in [0.86, 0.90, 0.95, 0.99]) {
        final pSafe = 1.0 - pScam;
        final r = engine.buildResultForTest(
          [pSafe, pScam, 0.0, 0.0],
          [],
          [],
        );
        expect(r.verdict, isNot(Verdict.scam),
            reason: 'Expected non-SCAM for pScam=$pScam with zero signals');
      }
    });

    // Any single signal enables the SCAM gate
    test('adding one signal enables SCAM gate at pScamTotal=0.90', () {
      final withoutSignal = engine.buildResultForTest(
        [0.10, 0.90, 0.0, 0.0], [], [],
      );
      final withSignal = engine.buildResultForTest(
        [0.10, 0.90, 0.0, 0.0],
        ['Urgency'],
        ['urgency'],
      );
      expect(withoutSignal.verdict, Verdict.safe);
      expect(withSignal.verdict, Verdict.scam);
    });
  });

  // =========================================================================
  // SUSPICIOUS conditions
  // =========================================================================

  group('Verdict mapping — SUSPICIOUS range (0.50–0.85] with signal', () {
    late MlEngine engine;
    setUp(() => engine = MlEngine());
    tearDown(() => engine.dispose());

    test('each value in 0.50<pScam<=0.85 with signal → SUSPICIOUS', () {
      for (final pScam in [0.51, 0.60, 0.70, 0.80, 0.85]) {
        final pSafe = 1.0 - pScam;
        final r = engine.buildResultForTest(
          [pSafe, pScam, 0.0, 0.0],
          ['Urgency'],
          ['urgency'],
        );
        expect(r.verdict, Verdict.suspicious,
            reason: 'Expected SUSPICIOUS for pScamTotal=$pScam');
        expect(r.verdict, isNot(Verdict.scam),
            reason: 'Should not be SCAM for pScamTotal=$pScam');
      }
    });

    test('high-signal upgrade: pScamTotal<=0.50, pSafe<0.75, lottery key → SUSPICIOUS', () {
      // pScamTotal=0.40 (not > 0.50, so SAFE by main logic)
      // pSafe=0.60 < 0.75 + 'lottery' high-signal key → upgrade to SUSPICIOUS
      final r = engine.buildResultForTest(
        [0.60, 0.40, 0.0, 0.0],
        [],
        ['lottery'],
      );
      expect(r.verdict, Verdict.suspicious);
      expect(r.ruleOverride, isTrue);
    });

    test('high-signal upgrade fires for digital_arrest key', () {
      final r = engine.buildResultForTest(
        [0.65, 0.35, 0.0, 0.0], [], ['digital_arrest'],
      );
      expect(r.verdict, Verdict.suspicious);
      expect(r.ruleOverride, isTrue);
    });

    test('high-signal upgrade fires for job_scam key', () {
      final r = engine.buildResultForTest(
        [0.70, 0.30, 0.0, 0.0], [], ['job_scam'],
      );
      expect(r.verdict, Verdict.suspicious);
    });

    test('high-signal upgrade fires for delivery_fee key', () {
      final r = engine.buildResultForTest(
        [0.70, 0.30, 0.0, 0.0], [], ['delivery_fee'],
      );
      expect(r.verdict, Verdict.suspicious);
    });

    test('high-signal upgrade does NOT fire when pSafe >= 0.75', () {
      // Model is confidently safe (pSafe=0.80) — do not upgrade
      final r = engine.buildResultForTest(
        [0.80, 0.20, 0.0, 0.0], [], ['lottery'],
      );
      expect(r.verdict, Verdict.safe);
      expect(r.ruleOverride, isFalse);
    });

    test('high-signal upgrade never promotes to SCAM, only SUSPICIOUS', () {
      final r = engine.buildResultForTest(
        [0.60, 0.40, 0.0, 0.0], [], ['digital_arrest'],
      );
      expect(r.verdict, isNot(Verdict.scam));
      expect(r.verdict, Verdict.suspicious);
    });

    test('broad-only key (phone_number) does NOT trigger upgrade', () {
      final r = engine.buildResultForTest(
        [0.60, 0.40, 0.0, 0.0], [], ['phone_number'],
      );
      expect(r.verdict, Verdict.safe);
      expect(r.ruleOverride, isFalse);
    });

    test('broad-only key (bank_impersonation) does NOT trigger upgrade', () {
      final r = engine.buildResultForTest(
        [0.60, 0.40, 0.0, 0.0], [], ['bank_impersonation'],
      );
      expect(r.verdict, Verdict.safe);
    });

    test('broad-only key (otp_request) does NOT trigger upgrade', () {
      final r = engine.buildResultForTest(
        [0.60, 0.40, 0.0, 0.0], [], ['otp_request'],
      );
      expect(r.verdict, Verdict.safe);
    });
  });

  // =========================================================================
  // SAFE conditions
  // =========================================================================

  group('Verdict mapping — SAFE conditions', () {
    late MlEngine engine;
    setUp(() => engine = MlEngine());
    tearDown(() => engine.dispose());

    test('pScamTotal<=0.50 with signals → SAFE (signals alone cannot flip)', () {
      final r = engine.buildResultForTest(
        [0.70, 0.30, 0.0, 0.0],
        ['Bank impersonation'],
        ['bank_impersonation'],
      );
      expect(r.verdict, Verdict.safe);
    });

    test('pScamTotal<=0.50 no signals → SAFE', () {
      final r = engine.buildResultForTest([0.90, 0.05, 0.025, 0.025], [], []);
      expect(r.verdict, Verdict.safe);
    });

    test('pScamTotal>0.50 no signals → SAFE with ruleOverride=true', () {
      final r = engine.buildResultForTest([0.10, 0.90, 0.0, 0.0], [], []);
      expect(r.verdict, Verdict.safe);
      expect(r.ruleOverride, isTrue);
    });

    test('strong-safe raw logits → SAFE with confidence > 0.99', () {
      final r = engine.buildResultForTest([10.0, -10.0, -10.0, -10.0], [], []);
      expect(r.verdict, Verdict.safe);
      expect(r.confidence, greaterThan(0.99));
    });

    test('category is "safe" when verdict is SAFE', () {
      final r = engine.buildResultForTest([0.9, 0.05, 0.025, 0.025], [], []);
      expect(r.verdict, Verdict.safe);
      expect(r.category, 'safe');
    });
  });

  // =========================================================================
  // triggerPhrases and firedSignalKeys are forwarded unchanged
  // =========================================================================

  group('Verdict mapping — payload forwarding', () {
    late MlEngine engine;
    setUp(() => engine = MlEngine());
    tearDown(() => engine.dispose());

    test('triggerPhrases forwarded into ScanResult', () {
      final r = engine.buildResultForTest(
        [0.0, 0.95, 0.05, 0.0],
        ['Shortened URL detected', 'Urgency'],
        ['shortened_url', 'urgency'],
      );
      expect(r.triggerPhrases, containsAll(['Shortened URL detected', 'Urgency']));
    });

    test('firedSignalKeys forwarded into ScanResult', () {
      final r = engine.buildResultForTest(
        [0.0, 0.95, 0.05, 0.0],
        ['Shortened URL detected'],
        ['shortened_url', 'urgency'],
      );
      expect(r.firedSignalKeys, containsAll(['shortened_url', 'urgency']));
    });

    test('empty lists forwarded without error', () {
      final r = engine.buildResultForTest([0.9, 0.05, 0.025, 0.025], [], []);
      expect(r.triggerPhrases, isEmpty);
      expect(r.firedSignalKeys, isEmpty);
    });

    test('throws StateError for logits length != 4', () {
      expect(
        () => engine.buildResultForTest([0.5, 0.5], [], []),
        throwsStateError,
      );
      expect(
        () => engine.buildResultForTest([0.2, 0.2, 0.2, 0.2, 0.2], [], []),
        throwsStateError,
      );
    });
  });
}
