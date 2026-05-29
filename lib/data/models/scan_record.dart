import 'dart:math';

import 'package:hive/hive.dart';

@HiveType(typeId: 0)
enum Verdict {
  @HiveField(0)
  safe,
  @HiveField(1)
  suspicious,
  @HiveField(2)
  scam,
}

@HiveType(typeId: 1)
class ScanRecord extends HiveObject {
  ScanRecord({
    required this.id,
    required this.sender,
    required this.body,
    required this.verdict,
    required this.confidence,
    required this.triggeredRules,
    required this.category,
    required this.timestamp,
    this.simSlot = 0,
  });

  @HiveField(0)
  String id;

  @HiveField(1)
  String sender;

  @HiveField(2)
  String body;

  @HiveField(3)
  Verdict verdict;

  @HiveField(4)
  double confidence;

  @HiveField(5)
  List<String> triggeredRules;

  @HiveField(6)
  String category;

  @HiveField(7)
  DateTime timestamp;

  @HiveField(8)
  int simSlot = 0;

  static String generateId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rand = Random.secure().nextInt(0x7fffffff);
    return '${now.toRadixString(16)}-${rand.toRadixString(16)}';
  }
}

// ---------- Manual TypeAdapters (no build_runner in this project) ----------

class VerdictAdapter extends TypeAdapter<Verdict> {
  @override
  final int typeId = 0;

  @override
  Verdict read(BinaryReader reader) => Verdict.values[reader.readByte()];

  @override
  void write(BinaryWriter writer, Verdict obj) => writer.writeByte(obj.index);
}

class ScanRecordAdapter extends TypeAdapter<ScanRecord> {
  @override
  final int typeId = 1;

  @override
  ScanRecord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ScanRecord(
      id: fields[0] as String,
      sender: fields[1] as String,
      body: fields[2] as String,
      verdict: fields[3] as Verdict,
      confidence: fields[4] as double,
      triggeredRules: (fields[5] as List).cast<String>(),
      category: fields[6] as String,
      timestamp: fields[7] as DateTime,
      simSlot: fields[8] as int? ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, ScanRecord obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.sender)
      ..writeByte(2)
      ..write(obj.body)
      ..writeByte(3)
      ..write(obj.verdict)
      ..writeByte(4)
      ..write(obj.confidence)
      ..writeByte(5)
      ..write(obj.triggeredRules)
      ..writeByte(6)
      ..write(obj.category)
      ..writeByte(7)
      ..write(obj.timestamp)
      ..writeByte(8)
      ..write(obj.simSlot);
  }
}
