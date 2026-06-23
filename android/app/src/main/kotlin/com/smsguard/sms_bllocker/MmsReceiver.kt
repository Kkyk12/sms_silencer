package com.smsguard.sms_bllocker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Required so the app qualifies as the default SMS app (the system checks that a
 * WAP_PUSH_DELIVER receiver is declared). Parsing MMS is out of scope for the
 * basic version, so this is intentionally a no-op.
 */
class MmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // No-op: MMS handling is not implemented in the basic version.
    }
}
