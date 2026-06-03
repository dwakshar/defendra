import 'package:flutter/services.dart';

class PhoneChannel {
  static const _channel = MethodChannel('defendra/phone');

  static Future<void> makeCall(String number) async {
    await _channel.invokeMethod<void>('makeCall', number);
  }
}
