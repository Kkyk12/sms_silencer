package com.smsguard.sms_bllocker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Clears per-sender notification history when the user swipes a notification away. */
class NotifDismissReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val sender = intent.getStringExtra("sender") ?: return
        NotificationHelper.clearHistory(sender)
    }
}
