import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../data/models/scan_record.dart';
import 'stats_aggregator.dart';

final statsRangeProvider = StateProvider<bool>((ref) => true); // true = week

final _allRecordsProvider = FutureProvider<List<ScanRecord>>((ref) async {
  if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(VerdictAdapter());
  if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ScanRecordAdapter());
  final box = await Hive.openBox<ScanRecord>('scan_results');
  return box.values.toList();
});

final statsDataProvider = Provider<AsyncValue<StatsData>>((ref) {
  final isWeek = ref.watch(statsRangeProvider);
  return ref.watch(_allRecordsProvider).whenData(
        (records) => StatsAggregator.compute(records, isWeek: isWeek),
      );
});
