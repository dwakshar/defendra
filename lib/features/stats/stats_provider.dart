import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../inbox/inbox_provider.dart';
import 'stats_aggregator.dart';

final statsRangeProvider = StateProvider<bool>((ref) => true); // true = week

final statsDataProvider = Provider<AsyncValue<StatsData>>((ref) {
  final isWeek = ref.watch(statsRangeProvider);
  final records = ref.watch(inboxNotifierProvider);
  return AsyncValue.data(StatsAggregator.compute(records, isWeek: isWeek));
});
