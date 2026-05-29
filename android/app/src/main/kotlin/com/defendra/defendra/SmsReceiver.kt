package com.defendra.defendra

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.telephony.SmsMessage
import android.util.Log
import io.flutter.plugin.common.MethodChannel

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
        val channel = methodChannel ?: return

        channel.invokeMethod(
            "onSmsReceived",
            mapOf(
                "sender" to sender,
                "body" to body,
                "timestamp" to timestamp,
                "simSlot" to simSlot,
            ),
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
    }
}
