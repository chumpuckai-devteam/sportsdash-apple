package com.samirpatel.sportsdash.core.epg

import java.io.ByteArrayInputStream
import java.io.FilterInputStream
import java.io.InputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class EpgRepositoryStreamTest {
    @Test
    fun parseXmltvAgreesOnOneByteAnd4kChunks() {
        val now = Date()
        val xml = sampleXmltv(now)
        val bytes = xml.toByteArray(Charsets.UTF_8)
        val repo = EpgRepository()
        val from4k = repo.parseXmltv(ByteArrayInputStream(bytes))
        val from1 = repo.parseXmltv(OneByteStream(ByteArrayInputStream(bytes)))
        assertEquals(from4k.keys, from1.keys)
        assertTrue("expected espn.us programmes", from4k.keys.any { it.contains("espn", ignoreCase = true) })
        val a = from4k.entries.first { it.key.contains("espn", ignoreCase = true) }.value
        val b = from1.entries.first { it.key.contains("espn", ignoreCase = true) }.value
        assertEquals(a.map { it.title }, b.map { it.title })
        assertTrue(a.any { it.title.contains("Monday") })
    }

    private fun sampleXmltv(now: Date): String {
        val hour = 3600_000L
        fun stamp(offsetMs: Long): String {
            val f = SimpleDateFormat("yyyyMMddHHmmss", Locale.US)
            f.timeZone = TimeZone.getTimeZone("UTC")
            return f.format(Date(now.time + offsetMs)) + " +0000"
        }
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <tv generator-info-name="test">
              <channel id="espn.us"><display-name>ESPN</display-name></channel>
              <programme start="${stamp(-30 * 60_000L)}" stop="${stamp(30 * 60_000L)}" channel="espn.us">
                <title lang="en">Monday Night &amp; More</title>
              </programme>
              <programme start="${stamp(2 * hour)}" stop="${stamp(3 * hour)}" channel="espn.us">
                <title>Later Show</title>
              </programme>
            </tv>
        """.trimIndent()
    }

    private class OneByteStream(src: InputStream) : FilterInputStream(src) {
        override fun read(b: ByteArray, off: Int, len: Int): Int {
            if (len <= 0) return 0
            return super.read(b, off, 1)
        }
    }
}
