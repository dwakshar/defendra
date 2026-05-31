import 'package:defendra/data/models/scan_record.dart';
import 'package:defendra/features/inbox/inbox_provider.dart';
import 'package:defendra/features/stats/stats_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ScanRecord _rec({
  required String id,
  required Verdict verdict,
  String category = 'none',
  Duration ago = const Duration(minutes: 10),
}) =>
    ScanRecord(
      id: id,
      sender: 'SENDER',
      body: 'body',
      verdict: verdict,
      confidence: verdict == Verdict.scam ? 0.92 : 0.05,
      triggeredRules: [],
      category: category,
      timestamp: DateTime.now().subtract(ago),
    );

Widget _buildStats(List<ScanRecord> records) {
  return ProviderScope(
    overrides: [
      inboxNotifierProvider.overrideWith(
        (ref) => InboxNotifier.preset(records, ref),
      ),
    ],
    child: const MaterialApp(
      home: StatsScreen(),
    ),
  );
}

void main() {
  // =========================================================================
  // Empty state
  // =========================================================================

  group('StatsScreen — empty state', () {
    testWidgets('shows empty state text when no records', (tester) async {
      await tester.pumpWidget(_buildStats([]));
      await tester.pump();

      expect(find.textContaining('no data yet'), findsOneWidget);
    });

    testWidgets('does not show headline stat cards when empty', (tester) async {
      await tester.pumpWidget(_buildStats([]));
      await tester.pump();

      expect(find.text('SMS SCANNED'), findsNothing);
    });
  });

  // =========================================================================
  // Headline metrics — large mono numbers
  // =========================================================================

  group('StatsScreen — headline metrics', () {
    testWidgets('SMS SCANNED count is correct', (tester) async {
      final records = [
        _rec(id: '1', verdict: Verdict.scam),
        _rec(id: '2', verdict: Verdict.safe),
        _rec(id: '3', verdict: Verdict.suspicious),
      ];

      await tester.pumpWidget(_buildStats(records));
      await tester.pump();

      expect(find.text('3'), findsWidgets); // totalScanned = 3
      expect(find.text('SMS SCANNED'), findsOneWidget);
    });

    testWidgets('SCAMS BLOCKED count is correct', (tester) async {
      final records = [
        _rec(id: '1', verdict: Verdict.scam),
        _rec(id: '2', verdict: Verdict.scam),
        _rec(id: '3', verdict: Verdict.safe),
      ];

      await tester.pumpWidget(_buildStats(records));
      await tester.pump();

      expect(find.text('2'), findsWidgets); // scamsBlocked = 2
      expect(find.text('SCAMS BLOCKED'), findsOneWidget);
    });

    testWidgets('estimated money saved renders as ₹Xk for large amounts', (tester) async {
      // 3 scams × ₹5000 = ₹15K
      final records = [
        _rec(id: '1', verdict: Verdict.scam),
        _rec(id: '2', verdict: Verdict.scam),
        _rec(id: '3', verdict: Verdict.scam),
      ];

      await tester.pumpWidget(_buildStats(records));
      await tester.pump();

      // BottomCards is below the fold; drag to bring it into the cacheExtent.
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pump();

      expect(find.text('₹15K'), findsOneWidget);
      expect(find.text('EST. SAVED'), findsOneWidget);
    });

    testWidgets('streak label is always present', (tester) async {
      final records = [_rec(id: '1', verdict: Verdict.safe)];

      await tester.pumpWidget(_buildStats(records));
      await tester.pump();

      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pump();

      expect(find.text('STREAK'), findsOneWidget);
    });

    testWidgets('streak is 1 when records exist only today', (tester) async {
      final records = [
        _rec(id: '1', verdict: Verdict.safe, ago: const Duration(minutes: 5)),
      ];

      await tester.pumpWidget(_buildStats(records));
      await tester.pump();

      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pump();

      expect(find.text('1d'), findsOneWidget);
    });
  });

  // =========================================================================
  // Range toggle — 7D / 30D
  // =========================================================================

  group('StatsScreen — range toggle', () {
    testWidgets('both "7D" and "30D" segments are visible', (tester) async {
      final records = [_rec(id: '1', verdict: Verdict.safe)];

      await tester.pumpWidget(_buildStats(records));
      await tester.pump();

      expect(find.text('7D'), findsOneWidget);
      expect(find.text('30D'), findsOneWidget);
    });

    testWidgets('tapping "30D" does not crash and keeps body visible', (tester) async {
      final records = [_rec(id: '1', verdict: Verdict.scam)];

      await tester.pumpWidget(_buildStats(records));
      await tester.pump();

      await tester.tap(find.text('30D'));
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.text('SMS SCANNED'), findsOneWidget);
    });

    testWidgets('30D range excludes records older than 30 days', (tester) async {
      final records = [
        _rec(id: '1', verdict: Verdict.scam, ago: const Duration(days: 5)),
        _rec(id: '2', verdict: Verdict.scam, ago: const Duration(days: 35)),
      ];

      await tester.pumpWidget(_buildStats(records));
      await tester.pump();

      // Tap 30D
      await tester.tap(find.text('30D'));
      await tester.pump();

      // Only 1 scam within 30 days
      expect(find.text('1'), findsWidgets); // scamsBlocked=1
    });
  });

  // =========================================================================
  // Verdict distribution section
  // =========================================================================

  group('StatsScreen — verdict distribution', () {
    testWidgets('VERDICT DISTRIBUTION section header is shown', (tester) async {
      final records = [_rec(id: '1', verdict: Verdict.safe)];

      await tester.pumpWidget(_buildStats(records));
      await tester.pump();

      expect(find.text('VERDICT DISTRIBUTION'), findsOneWidget);
    });

    testWidgets('safe / suspicious / scam verdict labels are present', (tester) async {
      final records = [
        _rec(id: '1', verdict: Verdict.scam),
        _rec(id: '2', verdict: Verdict.safe),
        _rec(id: '3', verdict: Verdict.suspicious),
      ];

      await tester.pumpWidget(_buildStats(records));
      await tester.pump();

      expect(find.text('safe'), findsOneWidget);
      expect(find.text('suspicious'), findsOneWidget);
      expect(find.text('scam'), findsOneWidget);
    });
  });

  // =========================================================================
  // Category breakdown section
  // =========================================================================

  group('StatsScreen — category breakdown', () {
    testWidgets('CATEGORY BREAKDOWN section header is shown', (tester) async {
      final records = [_rec(id: '1', verdict: Verdict.scam, category: 'kyc')];

      await tester.pumpWidget(_buildStats(records));
      await tester.pump();

      expect(find.text('CATEGORY BREAKDOWN'), findsOneWidget);
    });

    testWidgets('all six category labels are visible', (tester) async {
      final records = [_rec(id: '1', verdict: Verdict.scam, category: 'kyc')];

      await tester.pumpWidget(_buildStats(records));
      await tester.pump();

      for (final label in ['otp', 'kyc', 'delivery', 'job', 'lottery', 'other']) {
        expect(find.text(label), findsOneWidget, reason: 'Missing category: $label');
      }
    });
  });

  // =========================================================================
  // Scams over time section
  // =========================================================================

  group('StatsScreen — scams over time', () {
    testWidgets('SCAMS OVER TIME section header is shown', (tester) async {
      final records = [_rec(id: '1', verdict: Verdict.safe)];

      await tester.pumpWidget(_buildStats(records));
      await tester.pump();

      expect(find.text('SCAMS OVER TIME'), findsOneWidget);
    });

    testWidgets('"no scams detected" shown when no scam records in range', (tester) async {
      final records = [
        _rec(id: '1', verdict: Verdict.safe),
        _rec(id: '2', verdict: Verdict.suspicious),
      ];

      await tester.pumpWidget(_buildStats(records));
      await tester.pump();

      expect(find.text('no scams detected'), findsOneWidget);
    });
  });
}
