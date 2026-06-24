package com.smsguard.sms_bllocker

import android.app.role.RoleManager
import android.content.ContentValues
import android.content.Intent
import android.os.Build
import android.provider.ContactsContract
import android.provider.Telephony
import android.telephony.SmsManager
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

                    "getConversations" -> result.success(conversations())

                    "getThread" -> {
                        val address = call.argument<String>("address")
                        if (address.isNullOrBlank()) {
                            result.error("ARG", "address required", null)
                        } else {
                            result.success(thread(address))
                        }
                    }

                    "sendSms" -> {
                        val address = call.argument<String>("address")
                        val body = call.argument<String>("body")
                        if (address.isNullOrBlank() || body == null) {
                            result.error("ARG", "address and body required", null)
                        } else {
                            result.success(sendSms(address, body))
                        }
                    }

                    "markRead" -> {
                        val address = call.argument<String>("address")
                        if (!address.isNullOrBlank()) markThreadRead(address)
                        result.success(null)
                    }

                    "getContactName" -> {
                        val address = call.argument<String>("address")
                        result.success(if (address.isNullOrBlank()) null else contactName(address))
                    }

                    "testNotification" -> {
                        NotificationHelper.showSms(
                            this,
                            "SMS Guard",
                            "Test — messages that are allowed to ring will alert you like this.",
                            false,
                        )
                        result.success(null)
                    }

                    "getThemeMode" -> result.success(Prefs.getThemeMode(this))

                    "setThemeMode" -> {
                        Prefs.setThemeMode(this, call.argument<String>("mode") ?: "system")
                        result.success(null)
                    }

                    "deleteThread" -> {
                        val address = call.argument<String>("address")
                        result.success(if (address.isNullOrBlank()) false else deleteThread(address))
                    }

                    "deleteMessage" -> {
                        val id = call.argument<Number>("id")?.toLong()
                        result.success(if (id == null) false else deleteMessage(id))
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

    // ---- conversations / thread / send -------------------------------------

    /** Group key so different formats of the same number/sender collapse together. */
    private fun convKey(address: String): String {
        val digits = address.filter { it.isDigit() }
        return if (digits.length >= 7) digits.takeLast(10) else address.trim().lowercase()
    }

    /** Map of normalized phone number -> saved contact name (needs READ_CONTACTS). */
    private fun loadContactMap(): Map<String, String> {
        val map = HashMap<String, String>()
        try {
            val cursor = contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                arrayOf(
                    ContactsContract.CommonDataKinds.Phone.NUMBER,
                    ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                ),
                null, null, null,
            )
            cursor?.use { c ->
                val iNum = c.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
                val iName = c.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
                while (c.moveToNext()) {
                    val num = if (iNum >= 0) c.getString(iNum) else null
                    val name = if (iName >= 0) c.getString(iName) else null
                    if (!num.isNullOrBlank() && !name.isNullOrBlank()) {
                        map.putIfAbsent(convKey(num), name)
                    }
                }
            }
        } catch (_: Exception) {
        }
        return map
    }

    /** Saved contact name for one address, or null. */
    private fun contactName(address: String): String? = loadContactMap()[convKey(address)]

    /** One entry per conversation (latest first), with snippet + unread count. */
    private fun conversations(): List<Map<String, Any?>> {
        val order = LinkedHashMap<String, HashMap<String, Any?>>()
        val contacts = loadContactMap()
        val cursor = contentResolver.query(
            Telephony.Sms.CONTENT_URI,
            arrayOf(Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE, Telephony.Sms.TYPE, Telephony.Sms.READ),
            null, null, "${Telephony.Sms.DATE} DESC",
        )
        cursor?.use { c ->
            val iA = c.getColumnIndex(Telephony.Sms.ADDRESS)
            val iB = c.getColumnIndex(Telephony.Sms.BODY)
            val iD = c.getColumnIndex(Telephony.Sms.DATE)
            val iT = c.getColumnIndex(Telephony.Sms.TYPE)
            val iR = c.getColumnIndex(Telephony.Sms.READ)
            while (c.moveToNext()) {
                val addr = (if (iA >= 0) c.getString(iA) else null) ?: continue
                val key = convKey(addr)
                val type = if (iT >= 0) c.getInt(iT) else 1
                val read = if (iR >= 0) c.getInt(iR) else 1
                val existing = order[key]
                if (existing == null) {
                    order[key] = hashMapOf(
                        "address" to addr,
                        "name" to contacts[key],
                        "body" to (if (iB >= 0) c.getString(iB) else ""),
                        "date" to (if (iD >= 0) c.getLong(iD) else 0L),
                        "count" to 1,
                        "unread" to (if (type == Telephony.Sms.MESSAGE_TYPE_INBOX && read == 0) 1 else 0),
                        "silenced" to Prefs.isSilenced(this, addr),
                    )
                } else {
                    existing["count"] = (existing["count"] as Int) + 1
                    if (type == Telephony.Sms.MESSAGE_TYPE_INBOX && read == 0) {
                        existing["unread"] = (existing["unread"] as Int) + 1
                    }
                }
            }
        }
        return order.values.toList()
    }

    /** All messages with a given address, oldest first (for the chat view). */
    private fun thread(target: String): List<Map<String, Any?>> {
        val key = convKey(target)
        val out = ArrayList<Map<String, Any?>>()
        val cursor = contentResolver.query(
            Telephony.Sms.CONTENT_URI,
            arrayOf(Telephony.Sms._ID, Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE, Telephony.Sms.TYPE),
            null, null, "${Telephony.Sms.DATE} ASC",
        )
        cursor?.use { c ->
            val iId = c.getColumnIndex(Telephony.Sms._ID)
            val iA = c.getColumnIndex(Telephony.Sms.ADDRESS)
            val iB = c.getColumnIndex(Telephony.Sms.BODY)
            val iD = c.getColumnIndex(Telephony.Sms.DATE)
            val iT = c.getColumnIndex(Telephony.Sms.TYPE)
            while (c.moveToNext()) {
                val addr = (if (iA >= 0) c.getString(iA) else null) ?: continue
                if (convKey(addr) != key) continue
                val type = if (iT >= 0) c.getInt(iT) else 1
                out.add(
                    hashMapOf(
                        "id" to (if (iId >= 0) c.getLong(iId) else 0L),
                        "body" to (if (iB >= 0) c.getString(iB) else ""),
                        "date" to (if (iD >= 0) c.getLong(iD) else 0L),
                        "outgoing" to (type == Telephony.Sms.MESSAGE_TYPE_SENT),
                    ),
                )
            }
        }
        return out
    }

    /** Delete every message in a conversation. Needs to be the default SMS app. */
    private fun deleteThread(target: String): Boolean {
        return try {
            val key = convKey(target)
            val ids = ArrayList<Long>()
            val cursor = contentResolver.query(
                Telephony.Sms.CONTENT_URI,
                arrayOf(Telephony.Sms._ID, Telephony.Sms.ADDRESS),
                null, null, null,
            )
            cursor?.use { c ->
                val iId = c.getColumnIndex(Telephony.Sms._ID)
                val iA = c.getColumnIndex(Telephony.Sms.ADDRESS)
                while (c.moveToNext()) {
                    val addr = if (iA >= 0) c.getString(iA) else null
                    if (addr != null && convKey(addr) == key) ids.add(c.getLong(iId))
                }
            }
            for (id in ids) {
                contentResolver.delete(
                    Telephony.Sms.CONTENT_URI, "${Telephony.Sms._ID}=?", arrayOf(id.toString()),
                )
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun deleteMessage(id: Long): Boolean {
        return try {
            contentResolver.delete(
                Telephony.Sms.CONTENT_URI, "${Telephony.Sms._ID}=?", arrayOf(id.toString()),
            ) > 0
        } catch (_: Exception) {
            false
        }
    }

    private fun markThreadRead(target: String) {
        try {
            val key = convKey(target)
            val cursor = contentResolver.query(
                Telephony.Sms.Inbox.CONTENT_URI,
                arrayOf(Telephony.Sms._ID, Telephony.Sms.ADDRESS),
                "${Telephony.Sms.READ}=0", null, null,
            )
            cursor?.use { c ->
                val iId = c.getColumnIndex(Telephony.Sms._ID)
                val iA = c.getColumnIndex(Telephony.Sms.ADDRESS)
                while (c.moveToNext()) {
                    val addr = if (iA >= 0) c.getString(iA) else null
                    if (addr != null && convKey(addr) == key) {
                        val values = ContentValues().apply {
                            put(Telephony.Sms.READ, 1)
                            put(Telephony.Sms.SEEN, 1)
                        }
                        contentResolver.update(
                            Telephony.Sms.CONTENT_URI, values,
                            "${Telephony.Sms._ID}=?", arrayOf(c.getLong(iId).toString()),
                        )
                    }
                }
            }
        } catch (_: Exception) {
        }
    }

    /** Send an SMS and store it in the Sent box (default-app responsibility). */
    private fun sendSms(address: String, body: String): Boolean {
        return try {
            val sms = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }
            val parts = sms.divideMessage(body)
            if (parts.size > 1) {
                sms.sendMultipartTextMessage(address, null, parts, null, null)
            } else {
                sms.sendTextMessage(address, null, body, null, null)
            }
            try {
                val values = ContentValues().apply {
                    put(Telephony.Sms.ADDRESS, address)
                    put(Telephony.Sms.BODY, body)
                    put(Telephony.Sms.DATE, System.currentTimeMillis())
                    put(Telephony.Sms.READ, 1)
                    put(Telephony.Sms.SEEN, 1)
                    put(Telephony.Sms.TYPE, Telephony.Sms.MESSAGE_TYPE_SENT)
                }
                contentResolver.insert(Telephony.Sms.Sent.CONTENT_URI, values)
            } catch (_: Exception) {
            }
            true
        } catch (_: Exception) {
            false
        }
    }
}
