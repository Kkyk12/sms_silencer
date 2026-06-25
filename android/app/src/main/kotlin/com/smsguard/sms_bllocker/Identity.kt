package com.smsguard.sms_bllocker

/**
 * The single canonical identity for a sender, shared by every layer that needs
 * to answer "is this the same conversation / does this entry match this sender".
 *
 * Before this existed the answer was computed in four places that disagreed
 * (Prefs.matches, MainActivity.convKey, MarkReadReceiver.convKey and the Dart
 * `_convKey`), which split one Ethiopian contact into +251 / 09 / 9 threads and
 * leaked into silence/block/pin/folder/notification bugs. Route everything
 * through [normalize] / [matches] so there is exactly one rule.
 *
 * Mirror of `lib/identity.dart` — keep the two in sync.
 */
object Identity {

    /**
     * Canonical key for a sender. Ethiopian numbers collapse to their 9 national
     * digits so +251912345678, 0912345678 and 912345678 all become "912345678",
     * while 0911223344 stays distinct from numbers ending in different digits.
     * Alphanumeric sender IDs ("Safaricom") and short codes ("830") fall back to
     * their case-folded text so they compare exactly.
     */
    fun normalize(raw: String): String {
        val d = raw.filter { it.isDigit() }
        return when {
            // +251 9XXXXXXXX  /  251 9XXXXXXXX  (and any longer intl prefix)
            d.length >= 12 && d.startsWith("251") -> d.substring(3).takeLast(9)
            // 09XXXXXXXX (national, leading trunk 0)
            d.length == 10 && d.startsWith("0") -> d.substring(1)
            // Any other real phone number: compare the last 9 significant digits.
            d.length >= 9 -> d.takeLast(9)
            // Short codes ("830", "8161") and alphanumeric IDs ("Safaricom").
            else -> raw.trim().lowercase()
        }
    }

    /**
     * Does a silence/block list [entry] match an incoming [sender]?
     * Empty values never match. Everything else is decided by [normalize].
     */
    fun matches(entry: String, sender: String): Boolean {
        val e = entry.trim()
        val s = sender.trim()
        if (e.isEmpty() || s.isEmpty()) return false
        if (e.equals(s, ignoreCase = true)) return true
        return normalize(e) == normalize(s)
    }
}
