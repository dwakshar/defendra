import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/platform/sms_channel.dart';
import '../../core/notifications/notification_service.dart';
import '../../data/models/scan_record.dart';
import '../../ml/ml_engine.dart';

// ---------------------------------------------------------------------------
// smsStreamProvider
// ---------------------------------------------------------------------------

final smsStreamProvider = StreamProvider<SmsMessage>((ref) {
  final channel = SmsChannel();
  ref.onDispose(channel.dispose);
  return channel.incoming;
});

// ---------------------------------------------------------------------------
// InboxNotifier
// ---------------------------------------------------------------------------

class InboxNotifier extends StateNotifier<List<ScanRecord>> {
  InboxNotifier(this._ref) : super([]) {
    _init();
  }

  final Ref _ref;
  final MlEngine _engine = MlEngine();

  final _engineReady = Completer<void>();

  Future<void> _init() async {
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(VerdictAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(ScanRecordAdapter());
    }

    final box = await Hive.openBox<ScanRecord>('scan_results');
    if (mounted) {
      state = box.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }

    // Register the listener before awaiting load so SMS arriving during the
    // ~3–5 s model-load window are not dropped by the broadcast stream.
    _ref.listen<AsyncValue<SmsMessage>>(smsStreamProvider, (_, next) {
      next.whenData(_onSms);
    });

    await _engine.load();
    _engineReady.complete();
    debugPrint('[D0] engine ready, SMS listener active');
  }

  Future<void> _onSms(SmsMessage sms) async {
    debugPrint('[D3] notifier received sms from ${sms.sender}');
    await _engineReady.future;

    ScanResult result;
    try {
      result = await _engine.classify(sms.body);
    } catch (e, st) {
      debugPrint('[D3-ERR] classify failed: $e');
      debugPrintStack(label: '[D3-ERR]', stackTrace: st);
      result = const ScanResult(
        label: ScamLabel.safe,
        confidence: 0.0,
        triggerPhrases: [],
        ruleOverride: true,
      );
    }

    final label = result.label;
    final record = ScanRecord(
      id: ScanRecord.generateId(),
      sender: sms.sender,
      body: sms.body,
      verdict: _toVerdict(result),
      confidence: result.confidence,
      triggeredRules: result.triggerPhrases,
      category: label.labelDisplay,
      timestamp: sms.timestamp,
      simSlot: sms.simSlot,
    );
    debugPrint('[D4] verdict: ${record.verdict} conf: ${record.confidence}');

    final box = Hive.box<ScanRecord>('scan_results');
    await box.add(record);
    debugPrint('[D5] hive write done, state length will be: ${state.length + 1}');

    if (mounted) {
      state = [record, ...state];
    }

    if (record.verdict == Verdict.scam && record.confidence > 0.85) {
      await NotificationService.showScamAlert(record);
    }
  }

  Future<void> clearAll() async {
    final box = Hive.box<ScanRecord>('scan_results');
    await box.clear();
    if (mounted) state = [];
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }

  Verdict _toVerdict(ScanResult result) {
    if (!result.label.isScam) return Verdict.safe;
    return result.ruleOverride ? Verdict.suspicious : Verdict.scam;
  }
}

// ---------------------------------------------------------------------------
// inboxNotifierProvider
// ---------------------------------------------------------------------------

final inboxNotifierProvider =
    StateNotifierProvider<InboxNotifier, List<ScanRecord>>(
  (ref) => InboxNotifier(ref),
);

// ---------------------------------------------------------------------------
// inboxHistoryProvider — loads from Hive, sorted newest first
// ---------------------------------------------------------------------------

final inboxHistoryProvider = FutureProvider<List<ScanRecord>>((ref) async {
  if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(VerdictAdapter());
  if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ScanRecordAdapter());

  final box = await Hive.openBox<ScanRecord>('scan_results');
  return box.values.toList()
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
});
