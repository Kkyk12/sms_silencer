package com.smsguard.sms_bllocker

import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Telephony
import android.telephony.SmsManager
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

        try {
            val sms = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                context.getSystemService(SmsManager::class.java)
            else
                @Suppress("DEPRECATION") SmsManager.getDefault()

            val parts = sms.divideMessage(replyText)
            if (parts.size > 1) sms.sendMultipartTextMessage(sender, null, parts, null, null)
            else sms.sendTextMessage(sender, null, replyText, null, null)

            // Store in Sent box so it appears in the thread view
            val cv = ContentValues().apply {
                put(Telephony.Sms.ADDRESS, sender)
                put(Telephony.Sms.BODY, replyText)
                put(Telephony.Sms.DATE, System.currentTimeMillis())
                put(Telephony.Sms.READ, 1)
                put(Telephony.Sms.SEEN, 1)
                put(Telephony.Sms.TYPE, Telephony.Sms.MESSAGE_TYPE_SENT)
            }
            context.contentResolver.insert(Telephony.Sms.Sent.CONTENT_URI, cv)
        } catch (_: Exception) { }

        NotificationHelper.showReplySent(context, sender, replyText, notifId)
    }
}
