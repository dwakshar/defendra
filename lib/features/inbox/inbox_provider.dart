import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/platform/sms_channel.dart';
import '../../core/notifications/notification_service.dart';
import '../../data/models/scan_record.dart';
import '../../ml/ml_engine.dart';
import '../../ml/ml_engine_provider.dart';
import '../../ml/rule_matcher.dart';
import '../settings/settings_provider.dart';

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

  @visibleForTesting
  InboxNotifier.preset(super.records, Ref ref)
      : _ref = ref;

  final Ref _ref;

  Future<void> _init() async {
    // Register the SMS listener FIRST — before any async I/O — so the Dart
    // MethodCallHandler is live as early as possible.  Any Kotlin invokeMethod
    // call that arrives before this line is registered cannot be delivered;
    // moving it here shrinks that window to milliseconds instead of the full
    // Hive-open + model-load latency.
    _ref.listen<AsyncValue<SmsMessage>>(smsStreamProvider, (_, next) {
      next.whenData(_onSms);
    });

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

    // mlEngineProvider loads in the background — we don't block _init() here.
    // _classify() awaits the provider future on first SMS, which is the natural
    // gate: the engine must be ready before we can classify an SMS.
    debugPrint('[D0] InboxNotifier ready, SMS listener active');
  }

  // Classify [text] via the shared engine provider, falling back to rules-only
  // if the provider errored or hasn't resolved yet.
  Future<ClassificationResult> _classify(String text) async {
    try {
      final engine = await _ref.read(mlEngineProvider.future);
      return engine.classify(text);
    } catch (e) {
      debugPrint('[D3] engine unavailable — rule-only fallback ($e)');
      final (:reasons, :keys) = RuleMatcher.matchAll(text);
      return ClassificationResult(
        verdict: keys.isNotEmpty ? Verdict.suspicious : Verdict.safe,
        pScam: double.nan,
        probs: const [],
        source: VerdictSource.ruleFallback,
        triggers: keys,
        triggerReasons: reasons,
      );
    }
  }

  Future<void> _onSms(SmsMessage sms) async {
    debugPrint('[D3] notifier received sms from ${sms.sender}');

    final whitelist = _ref.read(whitelistProvider);
    if (whitelist.any((w) => sms.sender.toLowerCase() == w.toLowerCase())) {
      debugPrint('[D3-WL] ${sms.sender} whitelisted, skipping');
      return;
    }

    final blocklist = _ref.read(blocklistProvider);
    if (blocklist.any((b) => sms.sender.toLowerCase() == b.toLowerCase())) {
      debugPrint('[D3-BL] ${sms.sender} blocked, skipping');
      return;
    }

    final result = await _classify(sms.body);

    final record = ScanRecord(
      id: ScanRecord.generateId(),
      sender: sms.sender,
      body: sms.body,
      verdict: result.verdict,
      confidence: result.confidence,
      triggeredRules: result.triggerPhrases,
      category: result.category,
      timestamp: sms.timestamp,
      simSlot: sms.simSlot,
    );
    debugPrint(
      '[D4] verdict=${record.verdict}  conf=${record.confidence}  '
      'source=${result.source}',
    );

    // openBox returns the already-open box if available, or opens it if Hive
    // init succeeded but the box was closed (e.g., after a Hive error in _init).
    final box = await Hive.openBox<ScanRecord>('scan_results');
    await box.add(record);
    debugPrint('[D5] hive write done, state length will be: ${state.length + 1}');

    if (mounted) {
      state = [record, ...state];
    }

    final threshold = _ref.read(sensitivityProvider);
    if (record.verdict == Verdict.scam && record.confidence > threshold) {
      HapticFeedback.mediumImpact();
      await NotificationService.showScamAlert(record);
    }
  }

  Future<void> saveManual(ScanRecord record) async {
    final box = await Hive.openBox<ScanRecord>('scan_results');
    await box.add(record);
    if (mounted) state = [record, ...state];
  }

  Future<void> clearAll() async {
    final box = Hive.box<ScanRecord>('scan_results');
    await box.clear();
    if (mounted) state = [];
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
