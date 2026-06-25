package com.smsguard.sms_bllocker

import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Telephony
import android.telephony.SmsManager

/**
 * Shared persistence + send layer over the Telephony provider.
 *
 * Every writer (incoming receiver, in-app compose, inline reply, scheduled
 * send) goes through here so rows are written identically — crucially with a
 * THREAD_ID (so the system provider doesn't fork a second thread on the next
 * reply, B3) and with real send-status tracking instead of optimistically
 * recording every send as SENT (B4).
 */
object SmsStore {

    /** Broadcast (internal) fired after a send result lands, so the UI refreshes. */
    const val ACTION_SEND_STATUS = "com.smsguard.sms_bllocker.SEND_STATUS"
    const val EXTRA_ROW_ID = "row_id"

    /** Canonical provider thread id for an address; -1 if it can't be resolved. */
    private fun threadId(context: Context, address: String): Long =
        try {
            Telephony.Threads.getOrCreateThreadId(context, address)
        } catch (_: Exception) {
            -1L
        }

    private fun smsManager(context: Context, subId: Int): SmsManager =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val base = context.getSystemService(SmsManager::class.java)
            if (subId >= 0) base.createForSubscriptionId(subId) else base
        } else {
            @Suppress("DEPRECATION")
            if (subId >= 0) SmsManager.getSmsManagerForSubscriptionId(subId)
            else SmsManager.getDefault()
        }

    /** Store an incoming message in the inbox (the default app's responsibility). */
    fun insertInbox(
        context: Context,
        sender: String,
        body: String,
        timestamp: Long,
        subId: Int = -1,
    ): Uri? = try {
        val values = ContentValues().apply {
            put(Telephony.Sms.ADDRESS, sender)
            put(Telephony.Sms.BODY, body)
            put(Telephony.Sms.DATE, if (timestamp > 0) timestamp else System.currentTimeMillis())
            put(Telephony.Sms.READ, 0)
            put(Telephony.Sms.SEEN, 0)
            put(Telephony.Sms.TYPE, Telephony.Sms.MESSAGE_TYPE_INBOX)
            val tid = threadId(context, sender)
            if (tid >= 0) put(Telephony.Sms.THREAD_ID, tid)
            if (subId >= 0) put(Telephony.Sms.SUBSCRIPTION_ID, subId)
        }
        context.contentResolver.insert(Telephony.Sms.CONTENT_URI, values)
    } catch (_: Exception) {
        null
    }

    /**
     * Send an SMS and reflect its *real* outcome. The row is written first as
     * OUTBOX ("sending"); [SendStatusReceiver] then flips it to SENT or FAILED
     * when the radio reports back. Returns true if the send was dispatched
     * (delivery is confirmed asynchronously, not by this return value).
     */
    fun send(context: Context, address: String, body: String, subId: Int): Boolean = try {
        val sms = smsManager(context, subId)
        val parts = sms.divideMessage(body)

        // 1) Record up-front as OUTBOX so the thread shows it immediately.
        val values = ContentValues().apply {
            put(Telephony.Sms.ADDRESS, address)
            put(Telephony.Sms.BODY, body)
            put(Telephony.Sms.DATE, System.currentTimeMillis())
            put(Telephony.Sms.READ, 1)
            put(Telephony.Sms.SEEN, 1)
            put(Telephony.Sms.TYPE, Telephony.Sms.MESSAGE_TYPE_OUTBOX)
            val tid = threadId(context, address)
            if (tid >= 0) put(Telephony.Sms.THREAD_ID, tid)
            if (subId >= 0) put(Telephony.Sms.SUBSCRIPTION_ID, subId)
        }
        val rowUri = context.contentResolver.insert(Telephony.Sms.CONTENT_URI, values)
        val rowId = rowUri?.lastPathSegment?.toLongOrNull() ?: -1L

        // 2) Dispatch, carrying the row id back to SendStatusReceiver.
        val sentIntents = if (rowId >= 0) sentIntents(context, rowId, parts.size) else null
        if (parts.size > 1) {
            sms.sendMultipartTextMessage(address, null, parts, sentIntents, null)
        } else {
            sms.sendTextMessage(address, null, body, sentIntents?.firstOrNull(), null)
        }
        true
    } catch (_: Exception) {
        false
    }

    /** One immutable PendingIntent (reused per part) tagged with the row id. */
    private fun sentIntents(context: Context, rowId: Long, count: Int): ArrayList<PendingIntent> {
        val intent = Intent(context, SendStatusReceiver::class.java)
            .setPackage(context.packageName)
            .putExtra(EXTRA_ROW_ID, rowId)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        // Unique request code per row so concurrent sends never share a result.
        val pi = PendingIntent.getBroadcast(context, (rowId and 0x7FFFFFFF).toInt(), intent, flags)
        return ArrayList<PendingIntent>(count).apply { repeat(count) { add(pi) } }
    }

    /** Mark a row SENT only if still OUTBOX (so a part-failure can't be undone). */
    fun markSent(context: Context, rowId: Long) {
        try {
            context.contentResolver.update(
                Telephony.Sms.CONTENT_URI,
                ContentValues().apply { put(Telephony.Sms.TYPE, Telephony.Sms.MESSAGE_TYPE_SENT) },
                "${Telephony.Sms._ID}=? AND ${Telephony.Sms.TYPE}=?",
                arrayOf(rowId.toString(), Telephony.Sms.MESSAGE_TYPE_OUTBOX.toString()),
            )
        } catch (_: Exception) {}
    }

    /**
     * Mark a row FAILED. A failed part wins over a SENT part of the same
     * message, but we only transition from a non-terminal state (OUTBOX/SENT)
     * so a stray/duplicate broadcast can't clobber an already-FAILED row or a
     * retried row id.
     */
    fun markFailed(context: Context, rowId: Long, errorCode: Int) {
        try {
            context.contentResolver.update(
                Telephony.Sms.CONTENT_URI,
                ContentValues().apply {
                    put(Telephony.Sms.TYPE, Telephony.Sms.MESSAGE_TYPE_FAILED)
                    put(Telephony.Sms.ERROR_CODE, errorCode)
                },
                "${Telephony.Sms._ID}=? AND ${Telephony.Sms.TYPE} IN (?, ?)",
                arrayOf(
                    rowId.toString(),
                    Telephony.Sms.MESSAGE_TYPE_OUTBOX.toString(),
                    Telephony.Sms.MESSAGE_TYPE_SENT.toString(),
                ),
            )
        } catch (_: Exception) {}
    }
}
