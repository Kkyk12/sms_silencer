package com.smsguard.sms_bllocker

/**
 * Tiny, dependency-free reader for the one field we need out of an incoming
 * M-Notification.ind WAP-push PDU: the sender ("From"). We deliberately do not
 * pull in a full MMS/WSP stack (it would bloat the APK and the app doesn't
 * render media) — we only want to attribute the placeholder row to a sender so
 * the message isn't silently lost.
 *
 * Encoding per WAP-230 / OMA MMS: the From header is field 0x89, whose value is
 * `value-length` then either 0x80 (address-present-token) + encoded-string, or
 * 0x81 (insert-address-token). Addresses look like "+251911.../TYPE=PLMN".
 */
object MmsPdu {

    /** Best-effort sender address, or null if it can't be read. */
    fun parseFrom(data: ByteArray?): String? {
        if (data == null || data.isEmpty()) return null
        return try {
            var i = 0
            while (i < data.size) {
                val b = data[i].toInt() and 0xFF
                if (b == 0x89) { // From header
                    return readFromValue(data, i + 1)
                }
                i++
            }
            null
        } catch (_: Exception) {
            null
        }
    }

    private fun readFromValue(data: ByteArray, start: Int): String? {
        var i = start
        if (i >= data.size) return null
        // value-length: short (<=30) or 0x1F + uintvar length-quote.
        var len = data[i].toInt() and 0xFF
        i++
        if (len == 0x1F) {
            var v = 0
            while (i < data.size) {
                val o = data[i].toInt() and 0xFF; i++
                v = (v shl 7) or (o and 0x7F)
                if (o and 0x80 == 0) break
            }
            len = v
        }
        if (i >= data.size) return null
        val token = data[i].toInt() and 0xFF
        i++
        if (token == 0x81) return null // insert-address-token: sender hidden
        // token == 0x80 (address-present): an optional charset may precede text.
        if (i < data.size) {
            val first = data[i].toInt() and 0xFF
            if (first in 0x80..0xFF) i++ // single-byte charset
            else if (first == 0x1F) { // charset as uintvar
                i++
                while (i < data.size && (data[i].toInt() and 0x80) != 0) i++
                if (i < data.size) i++
            }
        }
        // Remaining bytes up to NUL are the address text.
        val sb = StringBuilder()
        while (i < data.size) {
            val c = data[i].toInt() and 0xFF
            if (c == 0) break
            sb.append(c.toChar())
            i++
        }
        val addr = sb.toString().substringBefore("/TYPE=").trim()
        return addr.ifEmpty { null }
    }
}
