package com.smsguard.sms_bllocker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The single source of truth for "same sender" — the bug that split one
 * Ethiopian contact into +251 / 09 / 9 threads (B1) — pinned down by tests so
 * it can't silently regress again.
 */
class IdentityTest {

    @Test
    fun ethiopianFormatsCollapseToOneKey() {
        val key = "912345678"
        assertEquals(key, Identity.normalize("+251912345678"))
        assertEquals(key, Identity.normalize("251912345678"))
        assertEquals(key, Identity.normalize("0912345678"))
        assertEquals(key, Identity.normalize("912345678"))
        assertEquals(key, Identity.normalize("+251 91-234-5678"))
    }

    @Test
    fun differentSubscribersStayDistinct() {
        assertFalse(Identity.normalize("0911223344") == Identity.normalize("0911223345"))
    }

    @Test
    fun shortCodesAndSenderIdsCompareAsText() {
        assertEquals("830", Identity.normalize("830"))
        assertEquals("8161", Identity.normalize("8161"))
        assertEquals("safaricom", Identity.normalize("Safaricom"))
        assertEquals("telebirr", Identity.normalize("telebirr"))
    }

    @Test
    fun matchesAcrossFormats() {
        assertTrue(Identity.matches("+251912345678", "0912345678"))
        assertTrue(Identity.matches("251912345678", "912345678"))
        assertTrue(Identity.matches("Awash Bank", "awash bank"))
    }

    @Test
    fun doesNotMatchDifferentOrEmpty() {
        assertFalse(Identity.matches("0911223344", "0911223345"))
        assertFalse(Identity.matches("", "0912345678"))
        assertFalse(Identity.matches("830", "0912345678"))
        // A short code must not match a long number that merely ends in it.
        assertFalse(Identity.matches("830", "0911000830"))
    }
}
