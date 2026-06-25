package com.smsguard.sms_bllocker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.RemoteInput

/**
 * Receives the inline-reply action from the notification and sends the SMS
 * without requiring the user to open the app.
 */
class ReplyReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val bundle = RemoteInput.getResultsFromIntent(intent) ?: return
        val replyText = bundle.getCharSequence(NotificationHelper.REPLY_KEY)
            ?.toString()?.trim() ?: return
        if (replyText.isEmpty()) return

        val sender = intent.getStringExtra("sender") ?: return
        val notifId = intent.getIntExtra("notif_id", 0)

        runAsync {
            // Send + persist with THREAD_ID and real send-status tracking.
            SmsStore.send(context, sender, replyText, subId = -1)
            NotificationHelper.showReplySent(context, sender, replyText, notifId)
        }
    }
}
