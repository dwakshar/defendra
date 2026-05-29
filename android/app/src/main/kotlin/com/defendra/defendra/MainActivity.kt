package com.defendra.defendra

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var smsChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        smsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "defendra/sms",
        ).also { channel ->
            // Kotlin → Dart only; no calls arrive from Dart on this channel.
            channel.setMethodCallHandler(null)
            SmsReceiver.methodChannel = channel
        }
    }

    override fun onDestroy() {
        SmsReceiver.methodChannel = null
        smsChannel?.setMethodCallHandler(null)
        smsChannel = null
        super.onDestroy()
    }
}
