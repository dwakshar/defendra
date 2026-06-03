package com.defendra.defendra

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var smsChannel: MethodChannel? = null
    private var phoneChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        smsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "defendra/sms",
        ).also { channel ->
            // Kotlin → Dart only; no calls arrive from Dart on this channel.
            channel.setMethodCallHandler(null)
            SmsReceiver.methodChannel = channel
            // Drain any SMS buffered while the app was killed.
            // The 2 s delay gives the Dart MethodCallHandler time to register
            // before the buffered messages are delivered.
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                SmsReceiver.drainBuffer(applicationContext, channel)
            }, 2_000L)
        }

        phoneChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "defendra/phone",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "makeCall") {
                    val number = call.arguments as? String
                    if (number != null) {
                        val intent = Intent(Intent.ACTION_CALL, Uri.parse("tel:$number"))
                        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        startActivity(intent)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARG", "number is null", null)
                    }
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onDestroy() {
        SmsReceiver.methodChannel = null
        smsChannel?.setMethodCallHandler(null)
        smsChannel = null
        phoneChannel?.setMethodCallHandler(null)
        phoneChannel = null
        super.onDestroy()
    }
}
