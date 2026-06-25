package com.smsguard.sms_bllocker

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

data class ChatFolder(val id: String, val name: String, val addresses: Set<String>)

/**
 * Single source of truth for the silence list, shared between the UI
 * (MainActivity) and the background SMS receiver.
 *
 * Model: senders on the silence list are muted; everyone else rings.
 *  - [DEFAULT_SILENCED] ships with the app and is silenced unless the user turns
 *    an entry off (stored in [KEY_UNSILENCED_DEFAULTS]).
 *  - The user can also add their own entries (stored in [KEY_CUSTOM_SILENCED]).
 *
 * Every mutator does a read-modify-write of SharedPreferences; the UI thread and
 * the alarm/receiver threads can race, so all mutations are serialized through
 * [lock] to avoid lost updates (B7).
 */
object Prefs {
    private const val PREFS_NAME = "sms_guard_prefs"
    private const val KEY_UNSILENCED_DEFAULTS = "unsilenced_defaults"
    private const val KEY_CUSTOM_SILENCED = "custom_silenced"

    /** Serializes read-modify-write sequences across UI + receiver threads. */
    private val lock = Any()

    /** Built-in automated/bulk senders, silenced by default. */
    val DEFAULT_SILENCED: List<String> = listOf(
        "131", "605", "623", "707", "7335", "8161", "8202", "824", "830", "942",
        "A.A Denb", "AATB", "ALXEthiopia", "apollo", "Awash Bank", "BeuDelivery",
        "CN", "DigitalEqub", "EAF", "EEU Info", "EFDA", "EoC", "EPHI", "EWF", "FCSC",
        "Fraud-Alert", "GOH BANK", "Hibret Bank", "IRCoE", "Mekedonia", "MoFA", "MoI",
        "MoLS", "MoT", "MoWSA", "MPESA Info", "National ID", "NEBE", "OrooDigital",
        "Safaricom", "SAMSUNG", "Sidama Reg", "Sitota", "telebirr", "telegames",
        "teleVAS", "WegagenBank", "ZemenGEBEYA",
    )

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun getSet(context: Context, key: String): MutableSet<String> =
        (prefs(context).getStringSet(key, emptySet()) ?: emptySet()).toMutableSet()

    private fun putSet(context: Context, key: String, value: Set<String>) {
        prefs(context).edit().putStringSet(key, value).apply()
    }

    // ---- Theme mode ("system" | "light" | "dark") ----
    fun getThemeMode(context: Context): String =
        prefs(context).getString("theme_mode", "system") ?: "system"

    fun setThemeMode(context: Context, mode: String) {
        prefs(context).edit().putString("theme_mode", mode).apply()
    }

    // ---- Default toggles ----------------------------------------------------

    /** Is this built-in default currently silenced? (true unless user turned it off) */
    fun isDefaultSilenced(context: Context, address: String): Boolean =
        !getSet(context, KEY_UNSILENCED_DEFAULTS).contains(address)

    fun setDefaultSilenced(context: Context, address: String, silenced: Boolean) = synchronized(lock) {
        val off = getSet(context, KEY_UNSILENCED_DEFAULTS)
        if (silenced) off.remove(address) else off.add(address)
        putSet(context, KEY_UNSILENCED_DEFAULTS, off)
    }

    // ---- User-added entries -------------------------------------------------

    fun getCustomSilenced(context: Context): List<String> =
        getSet(context, KEY_CUSTOM_SILENCED).toList().sortedBy { it.lowercase() }

    fun addCustomSilenced(context: Context, address: String) = synchronized(lock) {
        val trimmed = address.trim()
        if (trimmed.isEmpty()) return@synchronized
        val set = getSet(context, KEY_CUSTOM_SILENCED)
        set.add(trimmed)
        putSet(context, KEY_CUSTOM_SILENCED, set)
    }

    fun removeCustomSilenced(context: Context, address: String) = synchronized(lock) {
        val set = getSet(context, KEY_CUSTOM_SILENCED)
        set.remove(address.trim())
        putSet(context, KEY_CUSTOM_SILENCED, set)
    }

    // ---- Decision -----------------------------------------------------------

    /** Entries currently active for silencing: enabled defaults + custom additions. */
    private fun activeSilenced(context: Context): List<String> {
        val off = getSet(context, KEY_UNSILENCED_DEFAULTS)
        return DEFAULT_SILENCED.filterNot { off.contains(it) } + getCustomSilenced(context)
    }

    /** Should messages from this sender be silenced? */
    fun isSilenced(context: Context, sender: String): Boolean {
        val s = sender.trim()
        if (s.isEmpty()) return false
        return activeSilenced(context).any { Identity.matches(it, s) }
    }

    // ── Chat folders ─────────────────────────────────────────────────────────

    private const val KEY_FOLDERS = "chat_folders"

    fun getFolders(context: Context): List<ChatFolder> {
        val json = prefs(context).getString(KEY_FOLDERS, "[]") ?: "[]"
        return try {
            val arr = JSONArray(json)
            (0 until arr.length()).map { i ->
                val obj = arr.getJSONObject(i)
                val addrs = obj.optJSONArray("addrs") ?: JSONArray()
                ChatFolder(
                    id = obj.getString("id"),
                    name = obj.getString("name"),
                    addresses = (0 until addrs.length()).map { addrs.getString(it) }.toHashSet(),
                )
            }
        } catch (_: Exception) { emptyList() }
    }

    private fun saveFolders(context: Context, folders: List<ChatFolder>) {
        val arr = JSONArray()
        folders.forEach { f ->
            val obj = JSONObject()
            obj.put("id", f.id)
            obj.put("name", f.name)
            val addrs = JSONArray()
            f.addresses.forEach { addrs.put(it) }
            obj.put("addrs", addrs)
            arr.put(obj)
        }
        prefs(context).edit().putString(KEY_FOLDERS, arr.toString()).apply()
    }

    fun createFolder(context: Context, name: String): String = synchronized(lock) {
        val id = System.currentTimeMillis().toString()
        val folders = getFolders(context).toMutableList()
        folders.add(ChatFolder(id = id, name = name, addresses = emptySet()))
        saveFolders(context, folders)
        id
    }

    fun deleteFolder(context: Context, id: String) = synchronized(lock) {
        saveFolders(context, getFolders(context).filter { it.id != id })
    }

    fun addToFolder(context: Context, folderId: String, addresses: Set<String>) = synchronized(lock) {
        saveFolders(context, getFolders(context).map { f ->
            if (f.id == folderId) f.copy(addresses = f.addresses + addresses) else f
        })
    }

    // ── Pinned addresses ─────────────────────────────────────────────────────

    private const val KEY_PINNED = "pinned_addresses"

    fun getPinned(context: Context): Set<String> = getSet(context, KEY_PINNED).toSet()

    fun addPinned(context: Context, address: String) = synchronized(lock) {
        val key = Identity.normalize(address)
        val set = getSet(context, KEY_PINNED)
        // Drop any differently-formatted duplicate of the same contact first.
        set.removeAll { Identity.normalize(it) == key }
        set.add(address.trim())
        putSet(context, KEY_PINNED, set)
    }

    fun removePinned(context: Context, address: String) = synchronized(lock) {
        val key = Identity.normalize(address)
        val set = getSet(context, KEY_PINNED)
        set.removeAll { Identity.normalize(it) == key }
        putSet(context, KEY_PINNED, set)
    }

    /** Normalize-aware so a contact stays pinned even if its number format shifts. */
    fun isPinned(context: Context, address: String): Boolean {
        val key = Identity.normalize(address)
        return getSet(context, KEY_PINNED).any { Identity.normalize(it) == key }
    }

    // ── Blocked addresses ────────────────────────────────────────────────────

    private const val KEY_BLOCKED = "blocked_addresses"

    fun getBlocked(context: Context): List<String> =
        getSet(context, KEY_BLOCKED).toList().sortedBy { it.lowercase() }

    fun addBlocked(context: Context, address: String) = synchronized(lock) {
        val set = getSet(context, KEY_BLOCKED)
        set.add(address.trim())
        putSet(context, KEY_BLOCKED, set)
    }

    fun removeBlocked(context: Context, address: String) = synchronized(lock) {
        val set = getSet(context, KEY_BLOCKED)
        set.remove(address.trim())
        putSet(context, KEY_BLOCKED, set)
    }

    fun isBlocked(context: Context, sender: String): Boolean {
        val s = sender.trim()
        if (s.isEmpty()) return false
        return getSet(context, KEY_BLOCKED).any { Identity.matches(it, s) }
    }

    // ── Quick reply templates ────────────────────────────────────────────────

    private const val KEY_TEMPLATES = "quick_reply_templates"

    fun getTemplates(context: Context): List<String> {
        val json = prefs(context).getString(KEY_TEMPLATES, "[]") ?: "[]"
        return try {
            val arr = JSONArray(json)
            (0 until arr.length()).map { arr.getString(it) }
        } catch (_: Exception) { emptyList() }
    }

    fun saveTemplates(context: Context, templates: List<String>) = synchronized(lock) {
        val arr = JSONArray()
        templates.forEach { arr.put(it) }
        prefs(context).edit().putString(KEY_TEMPLATES, arr.toString()).apply()
    }

    // ── Scheduled messages ───────────────────────────────────────────────────

    private const val KEY_SCHEDULED = "scheduled_messages"
    private const val KEY_REQUEST_SEQ = "alarm_request_seq"

    data class ScheduledMsg(
        val id: String,
        val address: String,
        val body: String,
        val timeMillis: Long,
        /** Stable, unique AlarmManager request code (avoids hashCode collisions, B8). */
        val requestCode: Int,
    )

    /** Monotonic, collision-free request code for a new alarm. */
    fun nextRequestCode(context: Context): Int = synchronized(lock) {
        val next = prefs(context).getInt(KEY_REQUEST_SEQ, 1) + 1
        prefs(context).edit().putInt(KEY_REQUEST_SEQ, next).apply()
        next
    }

    fun getScheduled(context: Context): List<ScheduledMsg> {
        val json = prefs(context).getString(KEY_SCHEDULED, "[]") ?: "[]"
        return try {
            val arr = JSONArray(json)
            (0 until arr.length()).map { i ->
                val obj = arr.getJSONObject(i)
                ScheduledMsg(
                    id = obj.getString("id"),
                    address = obj.getString("address"),
                    body = obj.getString("body"),
                    timeMillis = obj.getLong("time"),
                    // Legacy rows had no requestCode; fall back to the old derivation.
                    requestCode = obj.optInt("rc", obj.getString("id").hashCode()),
                )
            }
        } catch (_: Exception) { emptyList() }
    }

    fun addScheduled(context: Context, msg: ScheduledMsg) = synchronized(lock) {
        val list = getScheduled(context).toMutableList()
        list.add(msg)
        saveScheduledList(context, list)
    }

    fun removeScheduled(context: Context, id: String) = synchronized(lock) {
        saveScheduledList(context, getScheduled(context).filter { it.id != id })
    }

    private fun saveScheduledList(context: Context, list: List<ScheduledMsg>) {
        val arr = JSONArray()
        list.forEach { m ->
            arr.put(JSONObject().apply {
                put("id", m.id); put("address", m.address); put("body", m.body)
                put("time", m.timeMillis); put("rc", m.requestCode)
            })
        }
        prefs(context).edit().putString(KEY_SCHEDULED, arr.toString()).apply()
    }

    /**
     * Match a list entry against an incoming sender. Delegates to the single
     * canonical rule in [Identity] so silence/block agree with grouping (B1).
     */
    fun matches(entry: String, sender: String): Boolean = Identity.matches(entry, sender)
}
