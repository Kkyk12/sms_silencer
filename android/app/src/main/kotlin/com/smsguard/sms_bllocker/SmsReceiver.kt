package com.smsguard.sms_bllocker

import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.provider.Telephony

/**
 * Receives every incoming SMS once this app is the default SMS app (the system
 * delivers SMS_DELIVER only to the default app). This runs even when the Flutter
 * UI is closed, so the decision logic lives here in native code.
 */
class SmsReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_DELIVER_ACTION) return

        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        if (parts.isEmpty()) return

        val sender = parts[0].displayOriginatingAddress
            ?: parts[0].originatingAddress
            ?: "Unknown"
        // A long SMS arrives split into parts; stitch the bodies back together.
        val body = parts.joinToString("") { it.displayMessageBody ?: it.messageBody ?: "" }
        val timestamp = parts[0].timestampMillis

        // Blocked senders: drop silently — no storage, no notification.
        if (Prefs.isBlocked(context, sender)) return

        // The default SMS app is responsible for storing messages in the provider.
        persistToInbox(context, sender, body, timestamp)

        // The core rule: silenced senders stay quiet; everyone else rings.
        val silenced = Prefs.isSilenced(context, sender)
        NotificationHelper.showSms(context, sender, body, silenced)

        // Tell the foreground app (if open) so it can show an in-app banner.
        context.sendBroadcast(
            Intent("com.smsguard.sms_bllocker.SMS_ARRIVED").apply {
                setPackage(context.packageName)
                putExtra("sender", sender)
                putExtra("body", body)
                putExtra("silenced", silenced)
            }
        )
    }

    private fun persistToInbox(context: Context, sender: String, body: String, timestamp: Long) {
        try {
            val values = ContentValues().apply {
                put(Telephony.Sms.ADDRESS, sender)
                put(Telephony.Sms.BODY, body)
                put(Telephony.Sms.DATE, if (timestamp > 0) timestamp else System.currentTimeMillis())
                put(Telephony.Sms.READ, 0)
                put(Telephony.Sms.SEEN, 0)
                put(Telephony.Sms.TYPE, Telephony.Sms.MESSAGE_TYPE_INBOX)
            }
            context.contentResolver.insert(Telephony.Sms.CONTENT_URI, values)
        } catch (_: Exception) {
            // Non-fatal for the basic version: a failed write just means the
            // message won't appear in the in-app list. The notification still fires.
        }
    }
}
