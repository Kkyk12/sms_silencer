package com.smsguard.sms_bllocker

import android.app.AlarmManager
import android.app.PendingIntent
import android.app.role.RoleManager
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.provider.ContactsContract
import android.provider.Telephony
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter UI and exposes the native SMS operations to Dart over a
 * MethodChannel. The UI never touches the SMS framework directly — it asks here.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "sms_guard/native"
    private val eventsChannelName = "sms_guard/events"
    private val roleRequestCode = 4231
    private var eventSink: EventChannel.EventSink? = null

    private val smsArrivedReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val sender = intent.getStringExtra("sender") ?: return
            val body = intent.getStringExtra("body") ?: return
            val silenced = intent.getBooleanExtra("silenced", false)
            if (!silenced) {
                eventSink?.success(hashMapOf("sender" to sender, "body" to body))
            }
        }
    }

    override fun onResume() {
        super.onResume()
        ContextCompat.registerReceiver(
            this, smsArrivedReceiver,
            IntentFilter("com.smsguard.sms_bllocker.SMS_ARRIVED"),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
    }

    override fun onPause() {
        super.onPause()
        try { unregisterReceiver(smsArrivedReceiver) } catch (_: Exception) {}
    }

    /**
     * Called when the app is already running and an external intent (e.g. tapping
     * the message icon on a contact in the phone dialer) opens it again.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent) // keep getIntent() fresh
        val addr = addressFromIntent(intent)
        if (addr != null) {
            eventSink?.success(hashMapOf("type" to "openThread", "address" to addr))
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        NotificationHelper.ensureChannels(this)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventsChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

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
                        val subId = call.argument<Int>("subId") ?: -1
                        if (address.isNullOrBlank() || body == null) {
                            result.error("ARG", "address and body required", null)
                        } else {
                            result.success(sendSms(address, body, subId))
                        }
                    }

                    "getSims" -> result.success(getSims())

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

                    "getFolders" -> result.success(folderList())

                    "createFolder" -> {
                        val name = call.argument<String>("name")
                        if (name.isNullOrBlank()) result.error("ARG", "name required", null)
                        else result.success(Prefs.createFolder(this, name))
                    }

                    "deleteFolder" -> {
                        val id = call.argument<String>("id")
                        if (id.isNullOrBlank()) result.error("ARG", "id required", null)
                        else { Prefs.deleteFolder(this, id); result.success(null) }
                    }

                    "addToFolder" -> {
                        val folderId = call.argument<String>("folderId")
                        val addresses = call.argument<List<String>>("addresses")
                        if (folderId.isNullOrBlank() || addresses == null) {
                            result.error("ARG", "folderId and addresses required", null)
                        } else {
                            Prefs.addToFolder(this, folderId, addresses.toSet())
                            result.success(null)
                        }
                    }

                    // ── Pinned ────────────────────────────────────────────────
                    "getPinned" -> result.success(Prefs.getPinned(this).toList())

                    "addPin" -> {
                        val address = call.argument<String>("address")
                        if (address.isNullOrBlank()) result.error("ARG", "address required", null)
                        else { Prefs.addPinned(this, address); result.success(null) }
                    }

                    "removePin" -> {
                        val address = call.argument<String>("address")
                        if (address.isNullOrBlank()) result.error("ARG", "address required", null)
                        else { Prefs.removePinned(this, address); result.success(null) }
                    }

                    // ── Blocked ───────────────────────────────────────────────
                    "getBlocked" -> result.success(Prefs.getBlocked(this))

                    "addBlocked" -> {
                        val address = call.argument<String>("address")
                        if (address.isNullOrBlank()) result.error("ARG", "address required", null)
                        else { Prefs.addBlocked(this, address); result.success(null) }
                    }

                    "removeBlocked" -> {
                        val address = call.argument<String>("address")
                        if (address.isNullOrBlank()) result.error("ARG", "address required", null)
                        else { Prefs.removeBlocked(this, address); result.success(null) }
                    }

                    // ── Templates ─────────────────────────────────────────────
                    "getTemplates" -> result.success(Prefs.getTemplates(this))

                    "saveTemplates" -> {
                        val templates = call.argument<List<String>>("templates")
                        if (templates == null) result.error("ARG", "templates required", null)
                        else { Prefs.saveTemplates(this, templates); result.success(null) }
                    }

                    // ── Scheduled messages ────────────────────────────────────
                    "scheduleMessage" -> {
                        val address = call.argument<String>("address")
                        val body = call.argument<String>("body")
                        val timeMillis = call.argument<Number>("timeMillis")?.toLong()
                        if (address.isNullOrBlank() || body == null || timeMillis == null) {
                            result.error("ARG", "address, body, timeMillis required", null)
                        } else {
                            val msgId = System.currentTimeMillis().toString() + "_" + (Math.random() * 10000).toInt()
                            val msg = Prefs.ScheduledMsg(msgId, address, body, timeMillis)
                            Prefs.addScheduled(this, msg)
                            val am = getSystemService(AlarmManager::class.java)
                            if (am != null) BootReceiver.scheduleAlarm(this, am, msgId, timeMillis)
                            result.success(msgId)
                        }
                    }

                    "cancelScheduledMessage" -> {
                        val msgId = call.argument<String>("msgId")
                        if (msgId.isNullOrBlank()) result.error("ARG", "msgId required", null)
                        else {
                            Prefs.removeScheduled(this, msgId)
                            BootReceiver.cancelAlarm(this, msgId)
                            result.success(null)
                        }
                    }

                    "getScheduledMessages" -> result.success(
                        Prefs.getScheduled(this).map { m ->
                            hashMapOf("id" to m.id, "address" to m.address, "body" to m.body, "timeMillis" to m.timeMillis)
                        }
                    )

                    // ── Contact photo ─────────────────────────────────────────
                    "getContactPhotoBytes" -> {
                        val photoUri = call.argument<String>("photoUri")
                        result.success(if (photoUri.isNullOrBlank()) null else getContactPhotoBytes(photoUri))
                    }

                    // ── Intent / deep-link address ────────────────────────────
                    "getInitialAddress" -> result.success(addressFromIntent(intent))

                    // ── Default SMS SIM ───────────────────────────────────────
                    "getDefaultSmsSubId" -> result.success(
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1)
                                SubscriptionManager.getDefaultSmsSubscriptionId()
                            else -1
                        } catch (_: Exception) { -1 }
                    )

                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Extract a phone number/address from an intent sent by the phone dialer or
     * another app. Handles sms:/smsto:/mms:/mmsto: URIs and plain extras.
     */
    private fun addressFromIntent(i: Intent?): String? {
        if (i == null) return null
        val data: Uri? = i.data
        if (data != null) {
            val scheme = data.scheme?.lowercase()
            if (scheme == "sms" || scheme == "smsto" || scheme == "mms" || scheme == "mmsto") {
                // "smsto://+2519..." → host contains the number
                val host = data.host
                if (!host.isNullOrBlank()) {
                    return Uri.decode(host).trim().takeIf { it.isNotEmpty() }
                }
                // "smsto:+2519..." → schemeSpecificPart contains the number
                val ssp = data.schemeSpecificPart
                if (!ssp.isNullOrBlank()) {
                    // Strip leading "//" and query params, e.g. "//+2519…?body=…"
                    val clean = ssp.trimStart('/').split("?").first().trim()
                    if (clean.isNotEmpty()) return Uri.decode(clean)
                }
                // Fallback: last path segment
                val seg = data.lastPathSegment
                if (!seg.isNullOrBlank()) return Uri.decode(seg).trim()
            }
        }
        // Standard extras used by various dialers
        val extraKeys = listOf(
            "address", "recipient", Intent.EXTRA_PHONE_NUMBER,
            Intent.EXTRA_TEXT, "sms_body", "phone_number",
        )
        for (key in extraKeys) {
            val v = i.getStringExtra(key)?.trim()
            if (!v.isNullOrEmpty()) return v
        }
        return null
    }

    private fun folderList(): List<Map<String, Any?>> =
        Prefs.getFolders(this).map { f ->
            hashMapOf("id" to f.id, "name" to f.name, "addresses" to f.addresses.toList())
        }

    /** Active SIM cards: subscription id, slot index, and a display label. */
    private fun getSims(): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP_MR1) return out
        try {
            val sm = getSystemService(SubscriptionManager::class.java) ?: return out
            val list = sm.activeSubscriptionInfoList ?: return out
            for (info in list) {
                val name = info.displayName?.toString()
                    ?: info.carrierName?.toString()
                    ?: "SIM ${info.simSlotIndex + 1}"
                out.add(
                    hashMapOf(
                        "subId" to info.subscriptionId,
                        "slot" to info.simSlotIndex,
                        "label" to name,
                    ),
                )
            }
        } catch (_: SecurityException) {
            // READ_PHONE_STATE not granted yet — no SIM info available.
        } catch (_: Exception) {
        }
        return out
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

    /** name map and photo-URI map, keyed by normalized number. */
    private fun loadContactMaps(): Pair<Map<String, String>, Map<String, String?>> {
        val names = HashMap<String, String>()
        val photos = HashMap<String, String?>()
        try {
            val cursor = contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                arrayOf(
                    ContactsContract.CommonDataKinds.Phone.NUMBER,
                    ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                    ContactsContract.Contacts.PHOTO_THUMBNAIL_URI,
                ),
                null, null, null,
            )
            cursor?.use { c ->
                val iNum = c.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
                val iName = c.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
                val iPhoto = c.getColumnIndex(ContactsContract.Contacts.PHOTO_THUMBNAIL_URI)
                while (c.moveToNext()) {
                    val num = if (iNum >= 0) c.getString(iNum) else null
                    val name = if (iName >= 0) c.getString(iName) else null
                    if (!num.isNullOrBlank() && !name.isNullOrBlank()) {
                        val key = convKey(num)
                        if (!names.containsKey(key)) {
                            names[key] = name
                            photos[key] = if (iPhoto >= 0) c.getString(iPhoto) else null
                        }
                    }
                }
            }
        } catch (_: Exception) {}
        return Pair(names, photos)
    }

    /** Saved contact name for one address, or null. */
    private fun contactName(address: String): String? = loadContactMaps().first[convKey(address)]

    /** Read raw bytes from a content:// photo thumbnail URI. */
    private fun getContactPhotoBytes(photoUri: String): ByteArray? = try {
        contentResolver.openInputStream(Uri.parse(photoUri))?.use { it.readBytes() }
    } catch (_: Exception) { null }

    /** One entry per conversation (latest first), with snippet + unread count. */
    private fun conversations(): List<Map<String, Any?>> {
        val order = LinkedHashMap<String, HashMap<String, Any?>>()
        val (contacts, photos) = loadContactMaps()
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
                        "pinned" to Prefs.isPinned(this, addr),
                        "blocked" to Prefs.isBlocked(this, addr),
                        "photoUri" to photos[key],
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
            arrayOf(Telephony.Sms._ID, Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE, Telephony.Sms.TYPE, Telephony.Sms.SUBSCRIPTION_ID),
            null, null, "${Telephony.Sms.DATE} ASC",
        )
        cursor?.use { c ->
            val iId = c.getColumnIndex(Telephony.Sms._ID)
            val iA = c.getColumnIndex(Telephony.Sms.ADDRESS)
            val iB = c.getColumnIndex(Telephony.Sms.BODY)
            val iD = c.getColumnIndex(Telephony.Sms.DATE)
            val iT = c.getColumnIndex(Telephony.Sms.TYPE)
            val iSub = c.getColumnIndex(Telephony.Sms.SUBSCRIPTION_ID)
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
                        "subId" to (if (iSub >= 0) c.getInt(iSub) else -1),
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

    /**
     * Send an SMS and store it in the Sent box (default-app responsibility).
     * [subId] selects which SIM to send on; -1 uses the system default.
     */
    private fun sendSms(address: String, body: String, subId: Int): Boolean {
        return try {
            val sms = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val base = getSystemService(SmsManager::class.java)
                if (subId >= 0) base.createForSubscriptionId(subId) else base
            } else {
                @Suppress("DEPRECATION")
                if (subId >= 0) SmsManager.getSmsManagerForSubscriptionId(subId)
                else SmsManager.getDefault()
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
                    if (subId >= 0) put(Telephony.Sms.SUBSCRIPTION_ID, subId)
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
