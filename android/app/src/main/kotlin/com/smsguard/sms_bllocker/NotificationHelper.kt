package com.smsguard.sms_bllocker

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.RemoteInput

object NotificationHelper {
    const val CHANNEL_RING = "messages_ring"
    const val CHANNEL_SILENCED = "messages_silenced"
    const val REPLY_KEY = "reply_text"

    /** Stable notification ID for a sender (one notification per sender). */
    fun notifId(sender: String): Int =
        sender.hashCode().let { if (it == Int.MIN_VALUE) 1 else Math.abs(it) }

    fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return

        val ring = NotificationChannel(
            CHANNEL_RING,
            "Ringing messages",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Messages from senders that are allowed to ring."
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
        if (silenced) return
        ensureChannels(context)

        val piFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        else PendingIntent.FLAG_UPDATE_CURRENT

        val launch = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
            ?.apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP }
        val contentIntent = PendingIntent.getActivity(context, 0, launch, piFlags)

        // ── Inline reply action ────────────────────────────────────────────
        val remoteInput = RemoteInput.Builder(REPLY_KEY)
            .setLabel("Reply…")
            .build()

        val id = notifId(sender)
        val replyPiFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        else PendingIntent.FLAG_UPDATE_CURRENT

        val replyIntent = Intent(context, ReplyReceiver::class.java).apply {
            putExtra("sender", sender)
            putExtra("notif_id", id)
        }
        val replyPi = PendingIntent.getBroadcast(context, id, replyIntent, replyPiFlags)

        val replyAction = NotificationCompat.Action.Builder(
            R.drawable.ic_stat_sms, "Reply", replyPi,
        ).addRemoteInput(remoteInput).build()
        // ──────────────────────────────────────────────────────────────────

        val builder = NotificationCompat.Builder(context, CHANNEL_RING)
            .setSmallIcon(R.drawable.ic_stat_sms)
            .setContentTitle(sender)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .addAction(replyAction)

        try {
            NotificationManagerCompat.from(context).notify(id, builder.build())
        } catch (_: SecurityException) { }
    }

    /** Called by ReplyReceiver after it successfully sends the reply. */
    fun showReplySent(context: Context, notifId: Int, sender: String) {
        ensureChannels(context)
        val builder = NotificationCompat.Builder(context, CHANNEL_RING)
            .setSmallIcon(R.drawable.ic_stat_sms)
            .setContentTitle(sender)
            .setContentText("Sent ✓")
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
        try {
            NotificationManagerCompat.from(context).notify(notifId, builder.build())
        } catch (_: SecurityException) { }
    }
}
