package com.smsguard.sms_bllocker

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Receives the send result for an outgoing SMS (delivered by SmsManager via the
 * sent PendingIntent) and flips the provider row from OUTBOX to SENT or FAILED.
 * Then broadcasts [SmsStore.ACTION_SEND_STATUS] so the UI can refresh.
 */
class SendStatusReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val rowId = intent.getLongExtra(SmsStore.EXTRA_ROW_ID, -1L)
        if (rowId < 0) return
        // Capture the radio's result before leaving onReceive's thread.
        val code = resultCode
        val ok = code == Activity.RESULT_OK

        runAsync {
            if (ok) SmsStore.markSent(context, rowId)
            else SmsStore.markFailed(context, rowId, code)

            context.sendBroadcast(
                Intent(SmsStore.ACTION_SEND_STATUS).setPackage(context.packageName),
            )
        }
    }
}
