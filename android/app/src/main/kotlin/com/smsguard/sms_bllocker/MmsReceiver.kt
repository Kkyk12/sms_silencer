package com.smsguard.sms_bllocker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Required so the app qualifies as the default SMS app (the system delivers
 * WAP_PUSH_DELIVER only to the default app's declared receiver).
 *
 * This app doesn't render media, but an incoming MMS must not vanish silently.
 * We read just the sender from the push PDU and persist a visible placeholder
 * row (+ notification), so the user sees that something arrived and from whom.
 */
class MmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val data = intent.getByteArrayExtra("data")
        runAsync {
            val sender = MmsPdu.parseFrom(data) ?: "MMS"
            if (Prefs.isBlocked(context, sender)) return@runAsync

            val body = "[Multimedia message]"
            SmsStore.insertInbox(context, sender, body, System.currentTimeMillis())

            val silenced = Prefs.isSilenced(context, sender)
            NotificationHelper.showSms(context, sender, body, silenced)

            context.sendBroadcast(
                Intent("com.smsguard.sms_bllocker.SMS_ARRIVED").apply {
                    setPackage(context.packageName)
                    putExtra("sender", sender)
                    putExtra("body", body)
                    putExtra("silenced", silenced)
                },
            )
        }
    }
}
