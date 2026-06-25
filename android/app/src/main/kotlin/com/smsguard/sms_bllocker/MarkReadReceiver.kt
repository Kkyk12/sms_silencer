package com.smsguard.sms_bllocker

import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import androidx.core.app.NotificationManagerCompat

/**
 * Handles the "Mark as read" notification action: flips the thread's unread
 * messages to read in the SMS provider, then clears and dismisses the
 * notification — all without opening the app.
 */
class MarkReadReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val sender = intent.getStringExtra("sender") ?: return
        val notifId = intent.getIntExtra("notif_id", NotificationHelper.notifId(sender))

        markThreadRead(context, sender)
        NotificationHelper.clearHistory(sender)
        NotificationManagerCompat.from(context).cancel(notifId)
    }

    /** Same conversation-key normalisation MainActivity uses. */
    private fun convKey(address: String): String {
        val digits = address.filter { it.isDigit() }
        return if (digits.length >= 7) digits.takeLast(10) else address.trim().lowercase()
    }

    private fun markThreadRead(context: Context, target: String) {
        try {
            val key = convKey(target)
            val cursor = context.contentResolver.query(
                Telephony.Sms.Inbox.CONTENT_URI,
                arrayOf(Telephony.Sms._ID, Telephony.Sms.ADDRESS),
                "${Telephony.Sms.READ}=0", null, null,
            )
            cursor?.use { c ->
                val iId = c.getColumnIndex(Telephony.Sms._ID)
                val iA = c.getColumnIndex(Telephony.Sms.ADDRESS)
                while (c.moveToNext()) {
                    val addr = if (iA >= 0) c.getString(iA) else null
                    if (addr != null && convKey(addr) == key) {
                        val values = ContentValues().apply {
                            put(Telephony.Sms.READ, 1)
                            put(Telephony.Sms.SEEN, 1)
                        }
                        context.contentResolver.update(
                            Telephony.Sms.CONTENT_URI, values,
                            "${Telephony.Sms._ID}=?", arrayOf(c.getLong(iId).toString()),
                        )
                    }
                }
            }
        } catch (_: Exception) {
        }
    }
}
