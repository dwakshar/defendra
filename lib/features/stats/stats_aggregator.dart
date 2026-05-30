import '../../data/models/scan_record.dart';

class DailyBucket {
  const DailyBucket({required this.date, required this.scamCount});
  final DateTime date;
  final int scamCount;
}

class StatsData {
  const StatsData({
    required this.totalScanned,
    required this.scamsBlocked,
    required this.safeCount,
    required this.suspiciousCount,
    required this.scamCount,
    required this.categoryBreakdown,
    required this.scamsOverTime,
    required this.estimatedMoneySaved,
    required this.streak,
  });

  final int totalScanned;
  final int scamsBlocked;
  final int safeCount;
  final int suspiciousCount;
  final int scamCount;
  final Map<String, int> categoryBreakdown;
  final List<DailyBucket> scamsOverTime;
  final double estimatedMoneySaved;
  final int streak;

  static const StatsData empty = StatsData(
    totalScanned: 0,
    scamsBlocked: 0,
    safeCount: 0,
    suspiciousCount: 0,
    scamCount: 0,
    categoryBreakdown: {
      'otp': 0,
      'kyc': 0,
      'delivery': 0,
      'job': 0,
      'lottery': 0,
      'other': 0,
    },
    scamsOverTime: [],
    estimatedMoneySaved: 0,
    streak: 0,
  );
}

class StatsAggregator {
  static StatsData compute(List<ScanRecord> all, {required bool isWeek}) {
    if (all.isEmpty) return StatsData.empty;

    final now = DateTime.now();
    final cutoff = isWeek
        ? now.subtract(const Duration(days: 7))
        : now.subtract(const Duration(days: 30));

    final records =
        all.where((r) => r.timestamp.isAfter(cutoff)).toList();

    final safe = records.where((r) => r.verdict == Verdict.safe).length;
    final suspicious =
        records.where((r) => r.verdict == Verdict.suspicious).length;
    final scam = records.where((r) => r.verdict == Verdict.scam).length;

    final cats = <String, int>{
      'otp': 0,
      'kyc': 0,
      'delivery': 0,
      'job': 0,
      'lottery': 0,
      'other': 0,
    };
    for (final r in records) {
      final key = cats.containsKey(r.category) ? r.category : 'other';
      cats[key] = (cats[key] ?? 0) + 1;
    }

    final buckets = _buildBuckets(records, days: isWeek ? 7 : 30, now: now);
    final streak = _computeStreak(all, now);

    return StatsData(
      totalScanned: records.length,
      scamsBlocked: scam,
      safeCount: safe,
      suspiciousCount: suspicious,
      scamCount: scam,
      categoryBreakdown: cats,
      scamsOverTime: buckets,
      estimatedMoneySaved: scam * 5000.0,
      streak: streak,
    );
  }

  static List<DailyBucket> _buildBuckets(
    List<ScanRecord> records, {
    required int days,
    required DateTime now,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    return List.generate(days, (i) {
      final date = today.subtract(Duration(days: days - 1 - i));
      final count = records.where((r) {
        final d = DateTime(r.timestamp.year, r.timestamp.month, r.timestamp.day);
        return d == date && r.verdict == Verdict.scam;
      }).length;
      return DailyBucket(date: date, scamCount: count);
    });
  }

  static int _computeStreak(List<ScanRecord> all, DateTime now) {
    if (all.isEmpty) return 0;
    final today = DateTime(now.year, now.month, now.day);
    final scannedDays = all
        .map((r) =>
            DateTime(r.timestamp.year, r.timestamp.month, r.timestamp.day))
        .toSet();

    int streak = 0;
    var cursor = today;
    while (scannedDays.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }
}
