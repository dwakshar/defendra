import 'package:flutter/painting.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../data/models/scan_record.dart';

const _kChannelId = 'defendra_alerts';

const _kChannel = AndroidNotificationChannel(
  _kChannelId,
  'Scam Alerts',
  importance: Importance.high,
  enableLights: true,
  ledColor: Color(0xFFFF4D4D),
  playSound: false,
  enableVibration: true,
);

const _kAndroidDetails = AndroidNotificationDetails(
  _kChannelId,
  'Scam Alerts',
  channelDescription: 'High-confidence scam SMS alerts',
  importance: Importance.high,
  priority: Priority.high,
  enableLights: true,
  ledColor: Color(0xFFFF4D4D),
  playSound: false,
  enableVibration: true,
  icon: '@mipmap/ic_launcher',
);

class NotificationService {
  NotificationService._();

  static final _plugin = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );

    await _plugin.initialize(settings: initSettings);

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_kChannel);
  }

  static Future<void> showScamAlert(ScanRecord record) async {
    await _plugin.show(
      id: record.id.hashCode.abs() & 0x7fffffff,
      title: 'Scam detected',
      body: '${record.sender} — ${record.category}',
      notificationDetails: const NotificationDetails(android: _kAndroidDetails),
      payload: record.id,
    );
  }
}
