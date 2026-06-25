package com.smsguard.sms_bllocker

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Re-schedules any pending scheduled messages after the device reboots,
 * since AlarmManager alarms are cleared on boot.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        runAsync {
            val now = System.currentTimeMillis()
            for (msg in Prefs.getScheduled(context)) {
                when {
                    // Still in the future: re-arm the alarm.
                    msg.timeMillis > now ->
                        scheduleAlarm(context, alarmManager, msg.requestCode, msg.id, msg.timeMillis)

                    // Recently overdue (phone was briefly off): send now.
                    now - msg.timeMillis <= STALE_AFTER_MS ->
                        context.sendBroadcast(
                            Intent(context, ScheduleReceiver::class.java).putExtra("msgId", msg.id),
                        )

                    // Too old to send safely (e.g. after a long power-off / restore):
                    // drop it instead of blasting a stale message, and tell the user.
                    else -> {
                        Prefs.removeScheduled(context, msg.id)
                        NotificationHelper.showSimple(
                            context,
                            "Scheduled message not sent",
                            "A message to ${msg.address} was too old to send after restart.",
                        )
                    }
                }
            }
        }
    }

    companion object {
        /** Overdue scheduled messages older than this at boot are dropped, not sent. */
        private const val STALE_AFTER_MS = 6 * 60 * 60_000L // 6 hours

        fun scheduleAlarm(
            context: Context,
            alarmManager: AlarmManager,
            requestCode: Int,
            msgId: String,
            timeMillis: Long,
        ) {
            val pi = PendingIntent.getBroadcast(
                context,
                requestCode,
                Intent(context, ScheduleReceiver::class.java).apply { putExtra("msgId", msgId) },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
                // No exact-alarm permission: use a 5-minute window instead.
                alarmManager.setWindow(AlarmManager.RTC_WAKEUP, timeMillis, 5 * 60_000L, pi)
            } else {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, timeMillis, pi)
            }
        }

        fun cancelAlarm(context: Context, requestCode: Int) {
            val pi = PendingIntent.getBroadcast(
                context,
                requestCode,
                Intent(context, ScheduleReceiver::class.java),
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
            ) ?: return
            (context.getSystemService(AlarmManager::class.java))?.cancel(pi)
        }
    }
}
