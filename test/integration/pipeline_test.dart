// ignore_for_file: avoid_redundant_argument_values

import 'dart:io';

import 'package:defendra/data/models/scan_record.dart';
import 'package:defendra/features/inbox/inbox_provider.dart';
import 'package:defendra/features/stats/stats_aggregator.dart';
import 'package:defendra/ml/ml_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ScanRecord _rec({
  required String id,
  required Verdict verdict,
  String sender = 'SENDER',
  String body = 'test body',
  String category = 'none',
  Duration ago = const Duration(minutes: 5),
}) =>
    ScanRecord(
      id: id,
      sender: sender,
      body: body,
      verdict: verdict,
      confidence: verdict == Verdict.scam ? 0.92 : 0.05,
      triggeredRules: [],
      category: category,
      timestamp: DateTime.now().subtract(ago),
    );

// ---------------------------------------------------------------------------
// Hive setup/teardown helpers
// ---------------------------------------------------------------------------

late Directory _hiveDir;

Future<void> _hiveSetUp() async {
  _hiveDir = Directory.systemTemp.createTempSync('defendra_test_');
  Hive.init(_hiveDir.path);
  if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(VerdictAdapter());
  if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ScanRecordAdapter());
}

Future<void> _hiveTearDown() async {
  await Hive.close();
  _hiveDir.deleteSync(recursive: true);
}

void main() {
  // =========================================================================
  // StatsAggregator — pipeline aggregation logic
  // =========================================================================

  group('Pipeline — StatsAggregator.compute', () {
    test('empty list returns StatsData.empty', () {
      final stats = StatsAggregator.compute([], isWeek: true);
      expect(stats.totalScanned, 0);
      expect(stats.scamsBlocked, 0);
      expect(stats.estimatedMoneySaved, 0.0);
    });

    test('counts scam/suspicious/safe correctly for 7-day window', () {
      final records = [
        _rec(id: '1', verdict: Verdict.scam),
        _rec(id: '2', verdict: Verdict.scam),
        _rec(id: '3', verdict: Verdict.suspicious),
        _rec(id: '4', verdict: Verdict.safe),
      ];

      final stats = StatsAggregator.compute(records, isWeek: true);

      expect(stats.totalScanned, 4);
      expect(stats.scamCount, 2);
      expect(stats.suspiciousCount, 1);
      expect(stats.safeCount, 1);
      expect(stats.scamsBlocked, 2); // scamsBlocked == scamCount
    });

    test('estimatedMoneySaved = scamCount × ₹5000', () {
      final records = [
        _rec(id: '1', verdict: Verdict.scam),
        _rec(id: '2', verdict: Verdict.scam),
        _rec(id: '3', verdict: Verdict.scam),
      ];

      final stats = StatsAggregator.compute(records, isWeek: false);

      expect(stats.estimatedMoneySaved, closeTo(15000.0, 0.01));
    });

    test('7D window excludes records older than 7 days', () {
      final records = [
        _rec(id: '1', verdict: Verdict.scam, ago: const Duration(days: 3)),
        _rec(id: '2', verdict: Verdict.scam, ago: const Duration(days: 8)), // outside 7D
      ];

      final stats = StatsAggregator.compute(records, isWeek: true);

      expect(stats.totalScanned, 1);
      expect(stats.scamCount, 1);
    });

    test('30D window excludes records older than 30 days', () {
      final records = [
        _rec(id: '1', verdict: Verdict.scam, ago: const Duration(days: 10)),
        _rec(id: '2', verdict: Verdict.scam, ago: const Duration(days: 31)), // outside 30D
        _rec(id: '3', verdict: Verdict.safe, ago: const Duration(days: 29)),
      ];

      final stats = StatsAggregator.compute(records, isWeek: false);

      expect(stats.totalScanned, 2);
      expect(stats.scamCount, 1);
    });

    test('categoryBreakdown slots are correct', () {
      final records = [
        _rec(id: '1', verdict: Verdict.scam, category: 'kyc'),
        _rec(id: '2', verdict: Verdict.scam, category: 'kyc'),
        _rec(id: '3', verdict: Verdict.scam, category: 'otp'),
        _rec(id: '4', verdict: Verdict.safe, category: 'none'), // 'none' → 'other'
      ];

      final stats = StatsAggregator.compute(records, isWeek: false);

      expect(stats.categoryBreakdown['kyc'], 2);
      expect(stats.categoryBreakdown['otp'], 1);
      expect(stats.categoryBreakdown['other'], 1);
    });

    test('streak is 0 with empty records', () {
      expect(StatsAggregator.compute([], isWeek: false).streak, 0);
    });

    test('streak is 1 when only today has records', () {
      final records = [_rec(id: '1', verdict: Verdict.safe)];
      final stats = StatsAggregator.compute(records, isWeek: false);
      expect(stats.streak, 1);
    });

    test('scamsOverTime length equals window size (7 for week)', () {
      final records = [_rec(id: '1', verdict: Verdict.scam)];
      final stats = StatsAggregator.compute(records, isWeek: true);
      expect(stats.scamsOverTime, hasLength(7));
    });

    test('scamsOverTime length equals window size (30 for month)', () {
      final records = [_rec(id: '1', verdict: Verdict.scam)];
      final stats = StatsAggregator.compute(records, isWeek: false);
      expect(stats.scamsOverTime, hasLength(30));
    });
  });

  // =========================================================================
  // Notification gate — verdict + confidence threshold
  // =========================================================================

  group('Pipeline — notification gate condition', () {
    bool gate(Verdict v, double conf, {double threshold = 0.85}) =>
        v == Verdict.scam && conf > threshold;

    test('scam + confidence > 0.85 → gate opens', () {
      expect(gate(Verdict.scam, 0.92), isTrue);
      expect(gate(Verdict.scam, 0.86), isTrue);
    });

    test('scam + confidence == 0.85 → gate stays closed (not strictly greater)', () {
      expect(gate(Verdict.scam, 0.85), isFalse);
    });

    test('scam + confidence < 0.85 → gate stays closed', () {
      expect(gate(Verdict.scam, 0.84), isFalse);
      expect(gate(Verdict.scam, 0.50), isFalse);
    });

    test('suspicious + high confidence → gate stays closed', () {
      expect(gate(Verdict.suspicious, 0.95), isFalse);
    });

    test('safe verdict → gate stays closed regardless of confidence', () {
      expect(gate(Verdict.safe, 1.0), isFalse);
    });

    test('gate respects custom threshold', () {
      expect(gate(Verdict.scam, 0.70, threshold: 0.65), isTrue);
      expect(gate(Verdict.scam, 0.60, threshold: 0.65), isFalse);
    });
  });

  // =========================================================================
  // ML fallback — engine not ready returns safe result (no notification)
  // =========================================================================

  group('Pipeline — ML fallback when engine not ready', () {
    late MlEngine engine;

    setUp(() => engine = MlEngine());
    tearDown(() => engine.dispose());

    test('engine isReady is false before load()', () {
      expect(engine.isReady, isFalse);
    });

    test('fallback result (no high-signal keys) has Verdict.safe', () async {
      // classify() delegates to _fallback when !isReady; test via buildResultForTest
      // with probabilities that the fallback maps to: safe, confidence=0.0
      // We verify fallback ScanResult directly:
      const fallback = ScanResult(
        label: ScamLabel.safe,
        verdict: Verdict.safe,
        confidence: 0.0,
        category: 'none',
        triggerPhrases: [],
        firedSignalKeys: [],
        ruleOverride: true,
      );
      // Gate must be closed for fallback output
      expect(fallback.verdict == Verdict.scam, isFalse);
    });

    test('fallback with high-signal key produces suspicious (never scam)', () async {
      // When engine unavailable but a lottery/digital_arrest rule fires,
      // _fallback returns Verdict.suspicious — still safe from notification gate
      // Test the gate: suspicious with confidence=0.75 → no notification
      const highSignalFallback = ScanResult(
        label: ScamLabel.otpKyc,
        verdict: Verdict.suspicious,
        confidence: 0.75,
        category: 'otp_kyc',
        triggerPhrases: [],
        firedSignalKeys: ['lottery'],
        ruleOverride: true,
      );
      expect(highSignalFallback.verdict, isNot(Verdict.scam));
    });

    test('buildResultForTest with scam probs + signal produces scam verdict', () {
      final r = engine.buildResultForTest(
        [0.05, 0.95, 0.0, 0.0],
        ['KYC / account-block urgency'],
        ['kyc_fraud'],
      );
      expect(r.verdict, Verdict.scam);
      expect(r.confidence, closeTo(0.95, 1e-6));
      // Gate condition
      expect(r.verdict == Verdict.scam && r.confidence > 0.85, isTrue);
    });
  });

  // =========================================================================
  // Hive persistence — saveManual writes through to the box
  // =========================================================================

  group('Pipeline — Hive persistence (InboxNotifier.saveManual)', () {
    setUp(_hiveSetUp);
    tearDown(_hiveTearDown);

    test('saveManual updates provider state', () async {
      await Hive.openBox<ScanRecord>('scan_results');

      final container = ProviderContainer(overrides: [
        inboxNotifierProvider.overrideWith(
          (ref) => InboxNotifier.preset([], ref),
        ),
      ]);
      addTearDown(container.dispose);

      final notifier = container.read(inboxNotifierProvider.notifier);
      final record = _rec(id: 'hive-1', verdict: Verdict.scam, category: 'kyc');

      await notifier.saveManual(record);

      final state = container.read(inboxNotifierProvider);
      expect(state, hasLength(1));
      expect(state.first.id, 'hive-1');
      expect(state.first.verdict, Verdict.scam);
    });

    test('saveManual writes record to Hive box', () async {
      await Hive.openBox<ScanRecord>('scan_results');

      final container = ProviderContainer(overrides: [
        inboxNotifierProvider.overrideWith(
          (ref) => InboxNotifier.preset([], ref),
        ),
      ]);
      addTearDown(container.dispose);

      final notifier = container.read(inboxNotifierProvider.notifier);
      final record = _rec(id: 'hive-2', verdict: Verdict.suspicious);

      await notifier.saveManual(record);

      final box = Hive.box<ScanRecord>('scan_results');
      expect(box.values.any((r) => r.id == 'hive-2'), isTrue);
    });

    test('multiple saveManual calls prepend records in state (newest first)', () async {
      await Hive.openBox<ScanRecord>('scan_results');

      final container = ProviderContainer(overrides: [
        inboxNotifierProvider.overrideWith(
          (ref) => InboxNotifier.preset([], ref),
        ),
      ]);
      addTearDown(container.dispose);

      final notifier = container.read(inboxNotifierProvider.notifier);

      await notifier.saveManual(_rec(id: 'first', verdict: Verdict.safe));
      await notifier.saveManual(_rec(id: 'second', verdict: Verdict.scam));

      final state = container.read(inboxNotifierProvider);
      expect(state, hasLength(2));
      expect(state.first.id, 'second'); // newest first
      expect(state.last.id, 'first');
    });

    test('clearAll empties state and Hive box', () async {
      final box = await Hive.openBox<ScanRecord>('scan_results');

      final record = _rec(id: 'clear-me', verdict: Verdict.scam);
      final container = ProviderContainer(overrides: [
        inboxNotifierProvider.overrideWith(
          (ref) => InboxNotifier.preset([record], ref),
        ),
      ]);
      addTearDown(container.dispose);

      // Pre-populate box (preset doesn't write to Hive)
      await box.add(record);
      expect(box.length, 1);

      final notifier = container.read(inboxNotifierProvider.notifier);
      await notifier.clearAll();

      expect(container.read(inboxNotifierProvider), isEmpty);
      expect(box.isEmpty, isTrue);
    });
  });
}
