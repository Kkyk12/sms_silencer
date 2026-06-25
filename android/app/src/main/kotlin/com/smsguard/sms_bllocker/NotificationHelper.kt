package com.smsguard.sms_bllocker

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Shader
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person
import androidx.core.app.RemoteInput

object NotificationHelper {
    const val CHANNEL_RING = "messages_ring"
    const val CHANNEL_SILENCED = "messages_silenced"
    const val REPLY_KEY = "reply_text"
    private const val BRAND_COLOR = 0xFF2F6BED.toInt()

    // Cached circular app logo used as the notification large icon.
    private var cachedLogo: Bitmap? = null

    private fun appLogo(context: Context): Bitmap? {
        cachedLogo?.let { return it }
        val src = BitmapFactory.decodeResource(
            context.resources, R.mipmap.ic_launcher
        ) ?: return null
        val size = minOf(src.width, src.height)
        if (size <= 0) return null
        val output = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val paint = Paint().apply {
            isAntiAlias = true
            shader = BitmapShader(src, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
        }
        val r = size / 2f
        canvas.drawCircle(r, r, r, paint)
        cachedLogo = output
        return output
    }

    private data class Msg(val body: String, val timestamp: Long, val fromMe: Boolean)

    // Per-sender message history so MessagingStyle can stack all messages.
    private val history = HashMap<String, ArrayDeque<Msg>>()

    fun clearHistory(sender: String) { history.remove(sender) }

    private fun addMsg(sender: String, body: String, fromMe: Boolean): List<Msg> {
        val q = history.getOrPut(sender) { ArrayDeque() }
        q.addLast(Msg(body, System.currentTimeMillis(), fromMe))
        while (q.size > 20) q.removeFirst()
        return q.toList()
    }

    /** Stable notification ID per sender address. */
    fun notifId(sender: String): Int =
        sender.hashCode().let { if (it == Int.MIN_VALUE) 1 else Math.abs(it) }

    fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val mgr = context.getSystemService(NotificationManager::class.java) ?: return
        mgr.createNotificationChannel(
            NotificationChannel(CHANNEL_RING, "Ringing messages",
                NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Messages from senders that are allowed to ring."
                enableVibration(true)
            }
        )
        mgr.createNotificationChannel(
            NotificationChannel(CHANNEL_SILENCED, "Silenced messages",
                NotificationManager.IMPORTANCE_LOW).apply {
                description = "Messages from silenced senders — no sound."
                enableVibration(false)
                setSound(null, null)
            }
        )
    }

    fun showSms(context: Context, sender: String, body: String, silenced: Boolean) {
        if (silenced) return
        ensureChannels(context)

        val id = notifId(sender)
        val msgs = addMsg(sender, body, fromMe = false)
        val isFirst = msgs.size == 1

        val immutable = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        else PendingIntent.FLAG_UPDATE_CURRENT

        val mutable = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        else PendingIntent.FLAG_UPDATE_CURRENT

        // Tap → open the specific thread
        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            data = Uri.parse("smsto:$sender")
        }
        val contentPi = PendingIntent.getActivity(context, id, openIntent, immutable)

        // Swipe-dismiss → clear stacked history for this sender
        val dismissPi = PendingIntent.getBroadcast(
            context, id,
            Intent(context, NotifDismissReceiver::class.java).putExtra("sender", sender),
            immutable
        )

        // Inline reply
        val replyPi = PendingIntent.getBroadcast(
            context, id,
            Intent(context, ReplyReceiver::class.java)
                .putExtra("sender", sender)
                .putExtra("notif_id", id),
            mutable
        )
        val replyAction = NotificationCompat.Action.Builder(
            R.drawable.ic_stat_sms, "Reply", replyPi
        ).addRemoteInput(
            RemoteInput.Builder(REPLY_KEY)
                .setLabel("Reply to $sender…")
                .build()
        ).setAllowGeneratedReplies(true).build()

        // Mark as read → flips the thread to read and dismisses the notification
        val markReadPi = PendingIntent.getBroadcast(
            context, id,
            Intent(context, MarkReadReceiver::class.java)
                .putExtra("sender", sender)
                .putExtra("notif_id", id),
            immutable
        )
        val markReadAction = NotificationCompat.Action.Builder(
            R.drawable.ic_notif_read, "Mark as read", markReadPi
        ).build()

        // MessagingStyle stacks all messages from this sender
        val me = Person.Builder().setName("You").setImportant(true).build()
        val them = Person.Builder().setName(sender).build()
        val style = NotificationCompat.MessagingStyle(me)
        for (m in msgs) {
            style.addMessage(m.body, m.timestamp, if (m.fromMe) null else them)
        }

        val builder = NotificationCompat.Builder(context, CHANNEL_RING)
            .setSmallIcon(R.drawable.ic_stat_sms)
            .setLargeIcon(appLogo(context))
            .setColor(BRAND_COLOR)
            .setStyle(style)
            .setAutoCancel(true)
            .setContentIntent(contentPi)
            .setDeleteIntent(dismissPi)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            // Only ring/vibrate for genuinely new notifications, not stacked updates
            .setOnlyAlertOnce(!isFirst)
            .addAction(replyAction)
            .addAction(markReadAction)

        if (isFirst) builder.setDefaults(NotificationCompat.DEFAULT_ALL)

        try { NotificationManagerCompat.from(context).notify(id, builder.build()) }
        catch (_: SecurityException) { }
    }

    /** Called by ReplyReceiver — adds the sent reply into the conversation bubble. */
    fun showReplySent(context: Context, sender: String, replyText: String, notifId: Int) {
        ensureChannels(context)
        val msgs = addMsg(sender, replyText, fromMe = true)

        val immutable = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        else PendingIntent.FLAG_UPDATE_CURRENT

        val dismissPi = PendingIntent.getBroadcast(
            context, notifId,
            Intent(context, NotifDismissReceiver::class.java).putExtra("sender", sender),
            immutable
        )

        val me = Person.Builder().setName("You").setImportant(true).build()
        val them = Person.Builder().setName(sender).build()
        val style = NotificationCompat.MessagingStyle(me)
        for (m in msgs) {
            style.addMessage(m.body, m.timestamp, if (m.fromMe) null else them)
        }

        val builder = NotificationCompat.Builder(context, CHANNEL_RING)
            .setSmallIcon(R.drawable.ic_stat_sms)
            .setLargeIcon(appLogo(context))
            .setColor(BRAND_COLOR)
            .setStyle(style)
            .setAutoCancel(true)
            .setDeleteIntent(dismissPi)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)

        try { NotificationManagerCompat.from(context).notify(notifId, builder.build()) }
        catch (_: SecurityException) { }
    }
}
