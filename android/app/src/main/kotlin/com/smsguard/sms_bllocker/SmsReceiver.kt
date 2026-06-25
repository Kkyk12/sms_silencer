package com.smsguard.sms_bllocker

import android.content.BroadcastReceiver
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

        // A genuinely address-less SMS is rare; keep the real originating address
        // so two different senders are never merged under one sentinel.
        val sender = parts[0].displayOriginatingAddress
            ?: parts[0].originatingAddress
            ?: "Unknown"
        // A long SMS arrives split into parts; stitch the bodies back together.
        val body = parts.joinToString("") { it.displayMessageBody ?: it.messageBody ?: "" }
        val timestamp = parts[0].timestampMillis
        val subId = intent.getIntExtra("subscription", -1)

        // Provider writes + notification are blocking work — keep the broadcast
        // alive on a background thread so we don't risk an ANR (B16).
        runAsync {
            // Blocked senders: drop silently — no storage, no notification.
            if (Prefs.isBlocked(context, sender)) return@runAsync

            // The default SMS app is responsible for storing messages (with a
            // THREAD_ID so replies thread correctly).
            SmsStore.insertInbox(context, sender, body, timestamp, subId)

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
                },
            )
        }
    }
}
