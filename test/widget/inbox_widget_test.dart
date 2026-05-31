import 'package:defendra/data/models/scan_record.dart';
import 'package:defendra/features/inbox/inbox_provider.dart';
import 'package:defendra/features/inbox/inbox_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Factory helpers
// ---------------------------------------------------------------------------

ScanRecord _record({
  required String id,
  required Verdict verdict,
  String sender = 'TEST',
  String body = 'body text',
}) =>
    ScanRecord(
      id: id,
      sender: sender,
      body: body,
      verdict: verdict,
      confidence: verdict == Verdict.scam
          ? 0.92
          : verdict == Verdict.suspicious
              ? 0.72
              : 0.05,
      triggeredRules: [],
      category: verdict == Verdict.scam ? 'kyc' : 'none',
      timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
    );

// Use InboxNotifier.preset() so no Hive/ML/SMS channel initialisation is needed.
Widget _buildTest(List<ScanRecord> records) {
  return ProviderScope(
    overrides: [
      inboxNotifierProvider.overrideWith(
        (ref) => InboxNotifier.preset(records, ref),
      ),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: const InboxScreen(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Mock permission_handler platform channel so _checkPermission() doesn't throw.
// ---------------------------------------------------------------------------

void _mockPermissions() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('flutter.baseflow.com/permissions/methods'),
    (call) async {
      if (call.method == 'checkPermissionStatus') return 1; // granted
      if (call.method == 'requestPermissions') return <int, int>{};
      return null;
    },
  );
}

void main() {
  setUp(_mockPermissions);

  // =========================================================================
  // Filter tabs — All / Scam / Suspicious / Safe
  // =========================================================================

  group('InboxScreen — filter tabs render', () {
    testWidgets('all four filter tab labels are visible', (tester) async {
      await tester.pumpWidget(_buildTest([]));
      await tester.pump(const Duration(milliseconds: 600)); // past shimmer

      expect(find.text('all'), findsOneWidget);
      expect(find.text('scam'), findsOneWidget);
      expect(find.text('suspicious'), findsOneWidget);
      expect(find.text('safe'), findsOneWidget);
    });

    testWidgets('tapping "scam" filter shows only scam records', (tester) async {
      final records = [
        _record(id: 'a', verdict: Verdict.scam, sender: 'SCAM-SENDER', body: 'scam body'),
        _record(id: 'b', verdict: Verdict.safe, sender: 'SAFE-SENDER', body: 'safe body'),
        _record(id: 'c', verdict: Verdict.suspicious, sender: 'SUS-SENDER', body: 'sus body'),
      ];

      await tester.pumpWidget(_buildTest(records));
      await tester.pump(const Duration(milliseconds: 600));

      await tester.tap(find.text('scam'));
      await tester.pumpAndSettle(); // wait for AnimatedSwitcher to complete

      expect(find.text('SCAM-SENDER'), findsOneWidget);
      expect(find.text('SAFE-SENDER'), findsNothing);
      expect(find.text('SUS-SENDER'), findsNothing);
    });

    testWidgets('tapping "safe" filter shows only safe records', (tester) async {
      final records = [
        _record(id: 'x', verdict: Verdict.scam, sender: 'SCAM-1'),
        _record(id: 'y', verdict: Verdict.safe, sender: 'SAFE-1'),
      ];

      await tester.pumpWidget(_buildTest(records));
      await tester.pump(const Duration(milliseconds: 600));

      await tester.tap(find.text('safe'));
      await tester.pumpAndSettle();

      expect(find.text('SAFE-1'), findsOneWidget);
      expect(find.text('SCAM-1'), findsNothing);
    });

    testWidgets('tapping "suspicious" filter shows only suspicious records', (tester) async {
      final records = [
        _record(id: 'p', verdict: Verdict.scam, sender: 'SC'),
        _record(id: 'q', verdict: Verdict.suspicious, sender: 'SU'),
        _record(id: 'r', verdict: Verdict.safe, sender: 'SA'),
      ];

      await tester.pumpWidget(_buildTest(records));
      await tester.pump(const Duration(milliseconds: 600));

      await tester.tap(find.text('suspicious'));
      await tester.pumpAndSettle();

      expect(find.text('SU'), findsOneWidget);
      expect(find.text('SC'), findsNothing);
      expect(find.text('SA'), findsNothing);
    });

    testWidgets('"all" filter shows all records after switching back', (tester) async {
      final records = [
        _record(id: '1', verdict: Verdict.scam, sender: 'SC'),
        _record(id: '2', verdict: Verdict.safe, sender: 'SA'),
      ];

      await tester.pumpWidget(_buildTest(records));
      await tester.pump(const Duration(milliseconds: 600));

      await tester.tap(find.text('scam'));
      await tester.pumpAndSettle();
      expect(find.text('SA'), findsNothing);

      await tester.tap(find.text('all'));
      await tester.pumpAndSettle();

      expect(find.text('SC'), findsOneWidget);
      expect(find.text('SA'), findsOneWidget);
    });
  });

  // =========================================================================
  // Status dots — circle decorations, NOT color blocks
  // =========================================================================

  group('InboxScreen — status dots are circles', () {
    testWidgets('each record card shows a circular dot container', (tester) async {
      final records = [
        _record(id: '1', verdict: Verdict.scam),
        _record(id: '2', verdict: Verdict.suspicious),
        _record(id: '3', verdict: Verdict.safe),
      ];

      await tester.pumpWidget(_buildTest(records));
      await tester.pump(const Duration(milliseconds: 600));

      // The dot is a Container with BoxDecoration(shape: BoxShape.circle)
      final circleDots = find.byWidgetPredicate((widget) {
        if (widget is! Container) return false;
        final dec = widget.decoration;
        return dec is BoxDecoration && dec.shape == BoxShape.circle;
      });

      // 3 records → at least 3 circle dots (one per card)
      expect(circleDots, findsAtLeastNWidgets(3));
    });

    testWidgets('scam dot has scam color (0xFFFF4D4D)', (tester) async {
      final records = [_record(id: '1', verdict: Verdict.scam)];

      await tester.pumpWidget(_buildTest(records));
      await tester.pump(const Duration(milliseconds: 600));

      final scamDot = find.byWidgetPredicate((widget) {
        if (widget is! Container) return false;
        final dec = widget.decoration;
        return dec is BoxDecoration &&
            dec.shape == BoxShape.circle &&
            dec.color == const Color(0xFFFF4D4D);
      });

      expect(scamDot, findsOneWidget);
    });

    testWidgets('safe dot has safe color (0xFF00D26A)', (tester) async {
      final records = [_record(id: '1', verdict: Verdict.safe)];

      await tester.pumpWidget(_buildTest(records));
      await tester.pump(const Duration(milliseconds: 600));

      final safeDot = find.byWidgetPredicate((widget) {
        if (widget is! Container) return false;
        final dec = widget.decoration;
        return dec is BoxDecoration &&
            dec.shape == BoxShape.circle &&
            dec.color == const Color(0xFF00D26A);
      });

      expect(safeDot, findsOneWidget);
    });

    testWidgets('suspicious dot has suspicious color (0xFFF5A623)', (tester) async {
      final records = [_record(id: '1', verdict: Verdict.suspicious)];

      await tester.pumpWidget(_buildTest(records));
      await tester.pump(const Duration(milliseconds: 600));

      final suspDot = find.byWidgetPredicate((widget) {
        if (widget is! Container) return false;
        final dec = widget.decoration;
        return dec is BoxDecoration &&
            dec.shape == BoxShape.circle &&
            dec.color == const Color(0xFFF5A623);
      });

      expect(suspDot, findsOneWidget);
    });

    testWidgets('empty inbox shows no list items (empty state)', (tester) async {
      await tester.pumpWidget(_buildTest([]));
      await tester.pump(const Duration(milliseconds: 600));

      // Empty state label visible; no circle dots in cards
      expect(find.textContaining('no messages'), findsOneWidget);
    });
  });

  // =========================================================================
  // Search
  // =========================================================================

  group('InboxScreen — search', () {
    testWidgets('search icon is present in app bar', (tester) async {
      await tester.pumpWidget(_buildTest([]));
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('tapping search icon expands the search bar', (tester) async {
      await tester.pumpWidget(_buildTest([]));
      await tester.pump(const Duration(milliseconds: 600));

      await tester.tap(find.byIcon(Icons.search));
      await tester.pump(const Duration(milliseconds: 200));

      // TextField should now be visible
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('search filters by sender', (tester) async {
      final records = [
        _record(id: '1', verdict: Verdict.scam, sender: 'HDFC-BANK'),
        _record(id: '2', verdict: Verdict.safe, sender: 'AIRTEL'),
      ];

      await tester.pumpWidget(_buildTest(records));
      await tester.pump(const Duration(milliseconds: 600));

      await tester.tap(find.byIcon(Icons.search));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.enterText(find.byType(TextField), 'HDFC');
      await tester.pump();

      expect(find.text('HDFC-BANK'), findsOneWidget);
      expect(find.text('AIRTEL'), findsNothing);
    });

    testWidgets('search filters by body text', (tester) async {
      final records = [
        _record(id: '1', verdict: Verdict.scam, body: 'Your KYC is expired'),
        _record(id: '2', verdict: Verdict.safe, body: 'Balance is Rs 500'),
      ];

      await tester.pumpWidget(_buildTest(records));
      await tester.pump(const Duration(milliseconds: 600));

      await tester.tap(find.byIcon(Icons.search));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.enterText(find.byType(TextField), 'KYC');
      await tester.pump();

      expect(find.textContaining('KYC'), findsWidgets);
      expect(find.textContaining('Balance'), findsNothing);
    });

    testWidgets('closing search (X icon) restores all records', (tester) async {
      final records = [
        _record(id: '1', verdict: Verdict.scam, sender: 'SC'),
        _record(id: '2', verdict: Verdict.safe, sender: 'SA'),
      ];

      await tester.pumpWidget(_buildTest(records));
      await tester.pump(const Duration(milliseconds: 600));

      await tester.tap(find.byIcon(Icons.search));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.enterText(find.byType(TextField), 'SC');
      await tester.pump();
      expect(find.text('SA'), findsNothing);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('SC'), findsOneWidget);
      expect(find.text('SA'), findsOneWidget);
    });
  });
}
