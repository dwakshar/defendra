import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class SmsMessage {
  const SmsMessage({
    required this.sender,
    required this.body,
    required this.timestamp,
    required this.simSlot,
  });

  final String sender;
  final String body;
  final DateTime timestamp;
  final int simSlot;

  factory SmsMessage._fromMap(Map<Object?, Object?> map) {
    return SmsMessage(
      sender: map['sender'] as String,
      body: map['body'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      simSlot: (map['simSlot'] as int?) ?? 0,
    );
  }
}

class SmsChannel {
  SmsChannel() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static const _channel = MethodChannel('defendra/sms');

  final _controller = StreamController<SmsMessage>.broadcast();

  Stream<SmsMessage> get incoming => _controller.stream;

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    debugPrint('[D1] method: ${call.method}');
    if (call.method != 'onSmsReceived') return;

    final raw = call.arguments as Map<Object?, Object?>;
    final message = SmsMessage._fromMap(raw);
    debugPrint('[D2] parsed: ${message.sender} | ${message.body}');

    if (!_controller.isClosed) {
      _controller.add(message);
    }
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    _controller.close();
  }
}
