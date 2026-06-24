package com.smsguard.sms_bllocker

import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Telephony
import android.telephony.SmsManager

/**
 * Fires when an AlarmManager alarm for a scheduled message is triggered.
 * Sends the SMS, stores it in the sent box, and removes it from Prefs.
 */
class ScheduleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val msgId = intent.getStringExtra("msgId") ?: return
        val msg = Prefs.getScheduled(context).firstOrNull { it.id == msgId } ?: return

        Prefs.removeScheduled(context, msgId)

        try {
            val sms = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                context.getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION") SmsManager.getDefault()
            }
            val parts = sms.divideMessage(msg.body)
            if (parts.size > 1) {
                sms.sendMultipartTextMessage(msg.address, null, parts, null, null)
            } else {
                sms.sendTextMessage(msg.address, null, msg.body, null, null)
            }
            val values = ContentValues().apply {
                put(Telephony.Sms.ADDRESS, msg.address)
                put(Telephony.Sms.BODY, msg.body)
                put(Telephony.Sms.DATE, System.currentTimeMillis())
                put(Telephony.Sms.READ, 1)
                put(Telephony.Sms.SEEN, 1)
                put(Telephony.Sms.TYPE, Telephony.Sms.MESSAGE_TYPE_SENT)
            }
            context.contentResolver.insert(Telephony.Sms.Sent.CONTENT_URI, values)
        } catch (_: Exception) {}

        // Tell the Flutter UI that a scheduled message was sent so it can refresh.
        context.sendBroadcast(
            Intent("com.smsguard.sms_bllocker.SCHEDULED_SENT").apply {
                setPackage(context.packageName)
                putExtra("address", msg.address)
            }
        )
    }
}
