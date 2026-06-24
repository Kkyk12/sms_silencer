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
        val now = System.currentTimeMillis()
        for (msg in Prefs.getScheduled(context)) {
            if (msg.timeMillis > now) {
                scheduleAlarm(context, alarmManager, msg.id, msg.timeMillis)
            } else {
                // Overdue — send immediately via broadcast
                context.sendBroadcast(
                    Intent(context, ScheduleReceiver::class.java).apply {
                        putExtra("msgId", msg.id)
                    }
                )
            }
        }
    }

    companion object {
        fun scheduleAlarm(context: Context, alarmManager: AlarmManager, msgId: String, timeMillis: Long) {
            val pi = PendingIntent.getBroadcast(
                context,
                msgId.hashCode(),
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

        fun cancelAlarm(context: Context, msgId: String) {
            val pi = PendingIntent.getBroadcast(
                context,
                msgId.hashCode(),
                Intent(context, ScheduleReceiver::class.java),
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
            ) ?: return
            (context.getSystemService(AlarmManager::class.java))?.cancel(pi)
        }
    }
}
