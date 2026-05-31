import 'package:defendra/data/models/scan_record.dart';
import 'package:defendra/features/inbox/inbox_provider.dart';
import 'package:defendra/features/scanner/scanner_provider.dart';
import 'package:defendra/features/scanner/scanner_screen.dart';
import 'package:defendra/ml/ml_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Builders — use .preset() to skip _init() and avoid Hive/model loading.
// ---------------------------------------------------------------------------

Widget _buildWithResult(ScanResult result) {
  return ProviderScope(
    overrides: [
      scannerProvider.overrideWith(
        (ref) => ScannerNotifier.preset(ScannerState(result: result)),
      ),
      inboxNotifierProvider.overrideWith(
        (ref) => InboxNotifier.preset([], ref),
      ),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: const ScannerScreen(),
    ),
  );
}

Widget _buildEmpty() {
  return ProviderScope(
    overrides: [
      scannerProvider.overrideWith(
        (ref) => ScannerNotifier.preset(const ScannerState()),
      ),
      inboxNotifierProvider.overrideWith(
        (ref) => InboxNotifier.preset([], ref),
      ),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: const ScannerScreen(),
    ),
  );
}

Widget _buildLoading() {
  return ProviderScope(
    overrides: [
      scannerProvider.overrideWith(
        (ref) => ScannerNotifier.preset(const ScannerState(isLoading: true)),
      ),
      inboxNotifierProvider.overrideWith(
        (ref) => InboxNotifier.preset([], ref),
      ),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: const ScannerScreen(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Pre-built scan results
// ---------------------------------------------------------------------------

const _scamResult = ScanResult(
  label: ScamLabel.otpKyc,
  verdict: Verdict.scam,
  confidence: 0.9200,
  category: 'kyc',
  triggerPhrases: ['KYC / account-block urgency', 'Urgency'],
  firedSignalKeys: ['kyc_fraud', 'urgency'],
);

const _suspResult = ScanResult(
  label: ScamLabel.deliveryCourier,
  verdict: Verdict.suspicious,
  confidence: 0.7100,
  category: 'delivery',
  triggerPhrases: ['Fake customs / delivery fee'],
  firedSignalKeys: ['delivery_fee'],
);

const _safeResult = ScanResult(
  label: ScamLabel.safe,
  verdict: Verdict.safe,
  confidence: 0.9500,
  category: 'none',
  triggerPhrases: [],
  firedSignalKeys: [],
);

void main() {
  // =========================================================================
  // App bar always renders "SCAN"
  // =========================================================================

  group('ScannerScreen — app bar', () {
    testWidgets('SCAN title is present', (tester) async {
      await tester.pumpWidget(_buildEmpty());
      await tester.pump();
      expect(find.text('SCAN'), findsWidgets); // AppBar title + body button both render 'SCAN'
    });

    testWidgets('scan button (SCAN label) is present when idle', (tester) async {
      await tester.pumpWidget(_buildEmpty());
      await tester.pump();
      // The OutlinedButton shows "SCAN" text (inside body, not appbar)
      expect(find.text('SCAN'), findsWidgets); // appBar + button
    });

    testWidgets('scan button is replaced by spinner when loading', (tester) async {
      await tester.pumpWidget(_buildLoading());
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  // =========================================================================
  // SCAM result card — verdict, confidence, trigger phrases
  // =========================================================================

  group('ScannerScreen — SCAM result card', () {
    testWidgets('verdict label "SCAM" is displayed', (tester) async {
      await tester.pumpWidget(_buildWithResult(_scamResult));
      await tester.pump();
      expect(find.text('SCAM'), findsOneWidget);
    });

    testWidgets('confidence percentage is displayed (92.0%)', (tester) async {
      await tester.pumpWidget(_buildWithResult(_scamResult));
      await tester.pump();
      expect(find.text('92.0%'), findsOneWidget);
    });

    testWidgets('each trigger phrase chip is displayed', (tester) async {
      await tester.pumpWidget(_buildWithResult(_scamResult));
      await tester.pump();
      expect(find.text('KYC / account-block urgency'), findsOneWidget);
      expect(find.text('Urgency'), findsOneWidget);
    });

    testWidgets('"View details" action link is present', (tester) async {
      await tester.pumpWidget(_buildWithResult(_scamResult));
      await tester.pump();
      expect(find.text('View details'), findsOneWidget);
    });

    testWidgets('"Save to inbox" link is present before saving', (tester) async {
      await tester.pumpWidget(_buildWithResult(_scamResult));
      await tester.pump();
      expect(find.text('Save to inbox'), findsOneWidget);
    });
  });

  // =========================================================================
  // SUSPICIOUS result card
  // =========================================================================

  group('ScannerScreen — SUSPICIOUS result card', () {
    testWidgets('verdict label "SUSPICIOUS" is displayed', (tester) async {
      await tester.pumpWidget(_buildWithResult(_suspResult));
      await tester.pump();
      expect(find.text('SUSPICIOUS'), findsOneWidget);
    });

    testWidgets('confidence percentage is displayed (71.0%)', (tester) async {
      await tester.pumpWidget(_buildWithResult(_suspResult));
      await tester.pump();
      expect(find.text('71.0%'), findsOneWidget);
    });

    testWidgets('trigger phrase chip rendered', (tester) async {
      await tester.pumpWidget(_buildWithResult(_suspResult));
      await tester.pump();
      expect(find.text('Fake customs / delivery fee'), findsOneWidget);
    });
  });

  // =========================================================================
  // SAFE result card
  // =========================================================================

  group('ScannerScreen — SAFE result card', () {
    testWidgets('verdict label "SAFE" is displayed', (tester) async {
      await tester.pumpWidget(_buildWithResult(_safeResult));
      await tester.pump();
      expect(find.text('SAFE'), findsOneWidget);
    });

    testWidgets('confidence 95.0% displayed', (tester) async {
      await tester.pumpWidget(_buildWithResult(_safeResult));
      await tester.pump();
      expect(find.text('95.0%'), findsOneWidget);
    });

    testWidgets('no trigger phrase chips when phrases list is empty', (tester) async {
      await tester.pumpWidget(_buildWithResult(_safeResult));
      await tester.pump();
      // The "KYC / account-block urgency" chip from other tests should not appear
      expect(find.text('KYC / account-block urgency'), findsNothing);
    });
  });

  // =========================================================================
  // RULE OVERRIDE badge
  // =========================================================================

  group('ScannerScreen — rule override badge', () {
    testWidgets('"RULE OVERRIDE" label shown when ruleOverride=true', (tester) async {
      const overrideResult = ScanResult(
        label: ScamLabel.otpKyc,
        verdict: Verdict.suspicious,
        confidence: 0.75,
        category: 'otp_kyc',
        triggerPhrases: ['Lottery / prize scam'],
        firedSignalKeys: ['lottery'],
        ruleOverride: true,
      );
      await tester.pumpWidget(_buildWithResult(overrideResult));
      await tester.pump();
      expect(find.text('RULE OVERRIDE'), findsOneWidget);
    });

    testWidgets('"RULE OVERRIDE" not shown when ruleOverride=false', (tester) async {
      await tester.pumpWidget(_buildWithResult(_scamResult)); // ruleOverride=false
      await tester.pump();
      expect(find.text('RULE OVERRIDE'), findsNothing);
    });
  });

  // =========================================================================
  // Paste from clipboard hint
  // =========================================================================

  group('ScannerScreen — empty state', () {
    testWidgets('"Paste from clipboard" link visible when input is empty', (tester) async {
      await tester.pumpWidget(_buildEmpty());
      await tester.pump();
      expect(find.textContaining('Paste from clipboard'), findsOneWidget);
    });

    testWidgets('example chips visible when input empty and no result', (tester) async {
      await tester.pumpWidget(_buildEmpty());
      await tester.pump();
      expect(find.textContaining('TRY AN EXAMPLE'), findsOneWidget);
    });
  });
}
