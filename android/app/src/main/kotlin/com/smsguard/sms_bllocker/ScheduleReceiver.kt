package com.smsguard.sms_bllocker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Fires when an AlarmManager alarm for a scheduled message is triggered.
 * Sends the SMS (with THREAD_ID + send-status tracking), then removes it from
 * Prefs and tells the UI to refresh.
 */
class ScheduleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val msgId = intent.getStringExtra("msgId") ?: return

        runAsync {
            val msg = Prefs.getScheduled(context).firstOrNull { it.id == msgId } ?: return@runAsync
            Prefs.removeScheduled(context, msgId)

            SmsStore.send(context, msg.address, msg.body, subId = -1)

            // Tell the Flutter UI that a scheduled message was sent so it refreshes.
            context.sendBroadcast(
                Intent("com.smsguard.sms_bllocker.SCHEDULED_SENT").apply {
                    setPackage(context.packageName)
                    putExtra("address", msg.address)
                },
            )
        }
    }
}
