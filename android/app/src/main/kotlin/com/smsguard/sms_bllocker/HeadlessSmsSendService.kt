package com.smsguard.sms_bllocker

import android.app.Service
import android.content.Intent
import android.os.IBinder

/**
 * Required so the app qualifies as the default SMS app (the system checks that a
 * RESPOND_VIA_MESSAGE service is declared, e.g. for replying to a call with a
 * text). Quick-reply sending is not implemented in the basic version.
 */
class HeadlessSmsSendService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        stopSelf(startId)
        return START_NOT_STICKY
    }
}
