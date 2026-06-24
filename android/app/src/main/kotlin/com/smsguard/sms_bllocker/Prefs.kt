package com.smsguard.sms_bllocker

import android.content.Context

/**
 * Single source of truth for the silence list, shared between the UI
 * (MainActivity) and the background SMS receiver.
 *
 * Model: senders on the silence list are muted; everyone else rings.
 *  - [DEFAULT_SILENCED] ships with the app and is silenced unless the user turns
 *    an entry off (stored in [KEY_UNSILENCED_DEFAULTS]).
 *  - The user can also add their own entries (stored in [KEY_CUSTOM_SILENCED]).
 */
object Prefs {
    private const val PREFS_NAME = "sms_guard_prefs"
    private const val KEY_UNSILENCED_DEFAULTS = "unsilenced_defaults"
    private const val KEY_CUSTOM_SILENCED = "custom_silenced"

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

    fun setDefaultSilenced(context: Context, address: String, silenced: Boolean) {
        val off = getSet(context, KEY_UNSILENCED_DEFAULTS)
        if (silenced) off.remove(address) else off.add(address)
        putSet(context, KEY_UNSILENCED_DEFAULTS, off)
    }

    // ---- User-added entries -------------------------------------------------

    fun getCustomSilenced(context: Context): List<String> =
        getSet(context, KEY_CUSTOM_SILENCED).toList().sortedBy { it.lowercase() }

    fun addCustomSilenced(context: Context, address: String) {
        val trimmed = address.trim()
        if (trimmed.isEmpty()) return
        val set = getSet(context, KEY_CUSTOM_SILENCED)
        set.add(trimmed)
        putSet(context, KEY_CUSTOM_SILENCED, set)
    }

    fun removeCustomSilenced(context: Context, address: String) {
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
        return activeSilenced(context).any { matches(it, s) }
    }

    /**
     * Match a list entry against an incoming sender.
     *  - Alphanumeric sender IDs (e.g. "Safaricom"): case-insensitive exact match.
     *  - Short codes (e.g. "830"): exact digit match.
     *  - Phone numbers: compare the last 9–10 digits so +251.., 0.. and 251.. agree.
     */
    fun matches(entry: String, sender: String): Boolean {
        val e = entry.trim()
        val s = sender.trim()
        if (e.equals(s, ignoreCase = true)) return true

        val ed = e.filter { it.isDigit() }
        val sd = s.filter { it.isDigit() }
        if (ed.isEmpty() || sd.isEmpty()) return false
        if (ed == sd) return true

        if (ed.length >= 9 && sd.length >= 9) {
            val n = minOf(ed.length, sd.length, 10)
            return ed.takeLast(n) == sd.takeLast(n)
        }
        return false
    }
}
