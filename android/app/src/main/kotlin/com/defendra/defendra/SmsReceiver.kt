package com.defendra.defendra

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.telephony.SmsMessage
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class SmsReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != "android.provider.Telephony.SMS_RECEIVED") return

        val timestamp = System.currentTimeMillis()
        val simSlot = resolveSimSlot(intent)
        val pdus = extractPdus(intent) ?: return
        val format = intent.getStringExtra("format")

        val messages = pdus.map { pdu ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                SmsMessage.createFromPdu(pdu, format)
            } else {
                @Suppress("DEPRECATION")
                SmsMessage.createFromPdu(pdu)
            }
        }

        if (messages.isEmpty()) return

        val sender = messages.first()?.originatingAddress ?: return
        val body = messages.joinToString(separator = "") { it?.messageBody ?: "" }

        Log.d("DEFENDRA", "[K1] SMS received from $sender")
        Log.d("DEFENDRA", "[K2] Channel null: ${methodChannel == null}")

        val channel = methodChannel
        if (channel == null) {
            // Flutter engine not running (app was killed). Buffer the SMS so
            // MainActivity can deliver it to Dart once the engine initialises.
            bufferSms(context, sender, body, timestamp, simSlot)
            return
        }

        channel.invokeMethod(
            "onSmsReceived",
            mapOf(
                "sender" to sender,
                "body" to body,
                "timestamp" to timestamp,
                "simSlot" to simSlot,
            ),
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    Log.d("DEFENDRA", "[K3] SMS delivered to Dart: $sender")
                }
                override fun error(code: String, msg: String?, details: Any?) {
                    // Dart handler threw — buffer so the record isn't lost.
                    Log.e("DEFENDRA", "[K3-ERR] invokeMethod error [$code] $msg — buffering")
                    bufferSms(context, sender, body, timestamp, simSlot)
                }
                override fun notImplemented() {
                    // Dart handler not registered yet (startup race window).
                    // Buffer so MainActivity drains it once Dart is ready.
                    Log.w("DEFENDRA", "[K3-WARN] Dart handler not registered — buffering")
                    bufferSms(context, sender, body, timestamp, simSlot)
                }
            },
        )
    }

    @Suppress("UNCHECKED_CAST")
    private fun extractPdus(intent: Intent): Array<ByteArray>? {
        val rawPdus = intent.extras?.get("pdus") as? Array<*> ?: return null
        return rawPdus.filterIsInstance<ByteArray>().takeIf { it.size == rawPdus.size }?.toTypedArray()
    }

    private fun resolveSimSlot(intent: Intent): Int {
        // Various OEM extras for SIM slot — common across Indian handsets (MTK, Qualcomm)
        val extras = intent.extras ?: return 0
        return extras.getInt("android.telephony.extra.SLOT_INDEX", -1)
            .takeIf { it >= 0 }
            ?: extras.getInt("slot", -1).takeIf { it >= 0 }
            ?: extras.getInt("simId", -1).takeIf { it >= 0 }
            ?: extras.getInt("phone", -1).takeIf { it >= 0 }
            ?: extras.getInt("subscription", -1).takeIf { it >= 0 }
            ?: 0
    }

    companion object {
        var methodChannel: MethodChannel? = null

        private const val PREFS_NAME = "defendra_pending"
        private const val PREFS_KEY = "pending_sms"

        fun bufferSms(
            context: Context,
            sender: String,
            body: String,
            timestamp: Long,
            simSlot: Int,
        ) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val existing = prefs.getString(PREFS_KEY, "[]") ?: "[]"
            val array = try { JSONArray(existing) } catch (_: Exception) { JSONArray() }
            array.put(
                JSONObject().apply {
                    put("sender", sender)
                    put("body", body)
                    put("timestamp", timestamp)
                    put("simSlot", simSlot)
                },
            )
            prefs.edit().putString(PREFS_KEY, array.toString()).apply()
            Log.d("DEFENDRA", "[K-BUF] Buffered SMS from $sender (${array.length()} pending)")
        }

        /** Delivers all buffered SMS to [channel] and clears the buffer. */
        fun drainBuffer(context: Context, channel: MethodChannel) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val json = prefs.getString(PREFS_KEY, "[]") ?: return
            val array = try { JSONArray(json) } catch (_: Exception) { return }
            if (array.length() == 0) return

            Log.d("DEFENDRA", "[K-DRAIN] Delivering ${array.length()} buffered SMS")
            for (i in 0 until array.length()) {
                val obj = array.optJSONObject(i) ?: continue
                channel.invokeMethod(
                    "onSmsReceived",
                    mapOf(
                        "sender" to (obj.optString("sender")),
                        "body" to (obj.optString("body")),
                        "timestamp" to (obj.optLong("timestamp", System.currentTimeMillis())),
                        "simSlot" to (obj.optInt("simSlot", 0)),
                    ),
                )
            }
            prefs.edit().remove(PREFS_KEY).apply()
        }
    }
}
