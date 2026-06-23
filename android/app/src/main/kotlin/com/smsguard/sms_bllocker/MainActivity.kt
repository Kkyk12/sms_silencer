package com.smsguard.sms_bllocker

import android.app.role.RoleManager
import android.content.Intent
import android.os.Build
import android.provider.Telephony
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter UI and exposes the native SMS operations to Dart over a
 * MethodChannel. The UI never touches the SMS framework directly — it asks here.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "sms_guard/native"
    private val roleRequestCode = 4231

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Make sure the notification channels exist as soon as the app opens.
        NotificationHelper.ensureChannels(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isDefaultSmsApp" -> result.success(isDefaultSmsApp())

                    "requestDefaultSmsApp" -> {
                        requestDefaultSmsApp()
                        result.success(null)
                    }

                    "getSilenceList" -> result.success(silenceList())

                    "setDefaultSilenced" -> {
                        val address = call.argument<String>("address")
                        val silenced = call.argument<Boolean>("silenced")
                        if (address.isNullOrBlank() || silenced == null) {
                            result.error("ARG", "address and silenced are required", null)
                        } else {
                            Prefs.setDefaultSilenced(this, address, silenced)
                            result.success(null)
                        }
                    }

                    "addCustom" -> {
                        val address = call.argument<String>("address")
                        if (address.isNullOrBlank()) {
                            result.error("ARG", "address is required", null)
                        } else {
                            Prefs.addCustomSilenced(this, address)
                            result.success(null)
                        }
                    }

                    "removeCustom" -> {
                        val address = call.argument<String>("address")
                        if (address.isNullOrBlank()) {
                            result.error("ARG", "address is required", null)
                        } else {
                            Prefs.removeCustomSilenced(this, address)
                            result.success(null)
                        }
                    }

                    "getMessages" -> result.success(readInbox())

                    else -> result.notImplemented()
                }
            }
    }

    private fun isDefaultSmsApp(): Boolean =
        Telephony.Sms.getDefaultSmsPackage(this) == packageName

    /** Ask the system to make us the default SMS app (the user must confirm). */
    private fun requestDefaultSmsApp() {
        if (isDefaultSmsApp()) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roleManager = getSystemService(RoleManager::class.java)
            if (roleManager != null &&
                roleManager.isRoleAvailable(RoleManager.ROLE_SMS) &&
                !roleManager.isRoleHeld(RoleManager.ROLE_SMS)
            ) {
                startActivityForResult(
                    roleManager.createRequestRoleIntent(RoleManager.ROLE_SMS),
                    roleRequestCode,
                )
            }
        } else {
            @Suppress("DEPRECATION")
            val intent = Intent(Telephony.Sms.Intents.ACTION_CHANGE_DEFAULT).apply {
                putExtra(Telephony.Sms.Intents.EXTRA_PACKAGE_NAME, packageName)
            }
            startActivity(intent)
        }
    }

    /** Defaults (with current on/off state) + user-added entries, for the UI. */
    private fun silenceList(): Map<String, Any?> {
        val defaults = Prefs.DEFAULT_SILENCED.map { address ->
            hashMapOf<String, Any?>(
                "address" to address,
                "silenced" to Prefs.isDefaultSilenced(this, address),
            )
        }
        return hashMapOf(
            "defaults" to defaults,
            "custom" to Prefs.getCustomSilenced(this),
        )
    }

    /** Read recent inbox messages for the in-app list. Needs READ_SMS at runtime. */
    private fun readInbox(): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        val projection = arrayOf(
            Telephony.Sms.ADDRESS,
            Telephony.Sms.BODY,
            Telephony.Sms.DATE,
        )
        val cursor = contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            projection,
            null,
            null,
            "${Telephony.Sms.DATE} DESC",
        )
        cursor?.use { c ->
            val iAddr = c.getColumnIndex(Telephony.Sms.ADDRESS)
            val iBody = c.getColumnIndex(Telephony.Sms.BODY)
            val iDate = c.getColumnIndex(Telephony.Sms.DATE)
            var count = 0
            while (c.moveToNext() && count < 300) {
                val address = if (iAddr >= 0) c.getString(iAddr) else null
                out.add(
                    hashMapOf(
                        "address" to address,
                        "body" to (if (iBody >= 0) c.getString(iBody) else null),
                        "date" to (if (iDate >= 0) c.getLong(iDate) else 0L),
                        "silenced" to (address != null && Prefs.isSilenced(this, address)),
                    ),
                )
                count++
            }
        }
        return out
    }
}
