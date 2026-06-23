package com.smsguard.sms_bllocker

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Builds the two kinds of notification this app produces:
 *  - ringing  -> high importance, makes sound + vibrates.
 *  - silenced -> low importance, completely silent (still visible in the shade).
 */
object NotificationHelper {
    const val CHANNEL_RING = "messages_ring"
    const val CHANNEL_SILENCED = "messages_silenced"

    /** Create the channels. Safe to call repeatedly — Android ignores duplicates. */
    fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return

        val ring = NotificationChannel(
            CHANNEL_RING,
            "Ringing messages",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Messages from senders that are allowed to ring. Plays a sound."
            enableVibration(true)
        }

        val silenced = NotificationChannel(
            CHANNEL_SILENCED,
            "Silenced messages",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Messages from silenced senders. No sound or vibration."
            enableVibration(false)
            setSound(null, null)
        }

        manager.createNotificationChannel(ring)
        manager.createNotificationChannel(silenced)
    }

    fun showSms(context: Context, sender: String, body: String, silenced: Boolean) {
        ensureChannels(context)

        val launch = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
            ?.apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP }

        val piFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val contentIntent = PendingIntent.getActivity(context, 0, launch, piFlags)

        val channel = if (silenced) CHANNEL_SILENCED else CHANNEL_RING
        val builder = NotificationCompat.Builder(context, channel)
            .setSmallIcon(R.drawable.ic_stat_sms)
            .setContentTitle(sender)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(contentIntent)

        if (silenced) {
            builder.priority = NotificationCompat.PRIORITY_LOW
            builder.setSilent(true)
        } else {
            // Pre-26 devices honour these; 26+ devices use the channel settings above.
            builder.priority = NotificationCompat.PRIORITY_HIGH
            builder.setDefaults(NotificationCompat.DEFAULT_ALL)
        }

        val id = (sender + "|" + body).hashCode()
        try {
            NotificationManagerCompat.from(context).notify(id, builder.build())
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS not granted (Android 13+). The message is still
            // saved to the inbox; we just can't show a heads-up for it.
        }
    }
}
