package com.smsguard.sms_bllocker

import android.content.BroadcastReceiver

/**
 * Run [block] off the main thread while holding the broadcast alive.
 *
 * SMS sending, provider inserts and cursor scans are all blocking work; doing
 * them inline in onReceive() risks an ANR (the system gives a receiver ~10s on
 * the main thread). [goAsync] keeps the process around until [block] finishes.
 */
fun BroadcastReceiver.runAsync(block: () -> Unit) {
    val pending = goAsync()
    Thread {
        try {
            block()
        } finally {
            pending.finish()
        }
    }.start()
}
