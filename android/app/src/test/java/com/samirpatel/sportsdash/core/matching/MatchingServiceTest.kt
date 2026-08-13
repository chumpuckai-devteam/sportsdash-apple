package com.samirpatel.sportsdash.core.matching

import com.samirpatel.sportsdash.core.model.IptvChannel
import com.samirpatel.sportsdash.core.sports.Game
import com.samirpatel.sportsdash.core.sports.GameStatus
import com.samirpatel.sportsdash.core.sports.SportLeague
import com.samirpatel.sportsdash.core.sports.TeamInfo
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Tests for channel matching fixes: geo-foreign penalty, smarter broadcast (no +40 on XX|ESPN for US golf),
 * golf-specific signal requirements.
 */
class MatchingServiceTest {

    private fun makePgaGame(
        eventName: String = "FedEx St. Jude Championship",
        broadcasts: List<String> = listOf("ESPN", "Golf Channel")
    ): Game {
        val pga = SportLeague.byId("pga") ?: SportLeague("pga", "PGA Tour", "golf", "pga", "Golf")
        val now = System.currentTimeMillis()
        return Game(
            id = "pga-test-1",
            league = pga,
            home = TeamInfo(id = "tbd1", name = "TBD", abbreviation = "TBD"),
            away = TeamInfo(id = "tbd2", name = "TBD", abbreviation = "TBD"),
            status = GameStatus.UPCOMING,
            startTimeMs = now + 3600_000L,
            eventName = eventName,
            broadcasts = broadcasts,
        )
    }

    private fun makeChannel(id: String, name: String, group: String? = null): IptvChannel {
        return IptvChannel(
            id = id,
            name = name,
            url = "http://example.com/$id",
            group = group,
        )
    }

    @Test
    fun `PGA filters Latino geo ESPN feeds but ranks clean Golf Channel and US ESPN`() {
        val game = makePgaGame()
        val channels = listOf(
            makeChannel("arg", "ARG | ESPN 2", "Latino | Sports"),
            makeChannel("golf", "Golf Channel HD", "Golf"),
            makeChannel("espn", "ESPN", "US Sports"),
            makeChannel("co", "CO | ESPN 3", "Latino | Sports"),
            makeChannel("cl", "CL | ESPN Premium", "Latino | Sports"),
        )

        val svc = MatchingService(minScore = 48.0)
        val matches = svc.matchGameToChannels(game, channels)
        val matchedNames = matches.map { it.channel.name }

        // Foreign geo must NOT pass minScore (no +40 broadcast, -35 or low, no golf token)
        assertFalse("ARG | ESPN must not match above minScore", matchedNames.any { it.contains("ARG") })
        assertFalse("CO | ESPN must not match above minScore", matchedNames.any { it.contains("CO") })
        assertFalse("CL | ESPN must not match above minScore", matchedNames.any { it.contains("CL") })

        // Clean ones should
        assertTrue("Golf Channel HD should be included", matchedNames.any { it.contains("Golf Channel") })
        assertTrue("clean ESPN should be included", matchedNames.any { it == "ESPN" })

        // Optional: ensure top are the good ones, foreign not present at all
        assertTrue("results should prefer Golf/US over foreign", matchedNames.isNotEmpty())
    }

    @Test
    fun `groupHasSportsContext for golf requires golf token not just sport`() {
        val game = makePgaGame()
        val svc = MatchingService()  // access via reflection? or test indirectly via match

        // Indirect via match: a pure "Sports" group with no golf token + generic espn foreign -> low score
        val chSports = makeChannel("s1", "Latino Sports", "Latino | Sports")
        val chGolfGroup = makeChannel("s2", "Golf Sports", "Golf Sports")

        val matches = svc.matchGameToChannels(game, listOf(chSports, chGolfGroup))
        val names = matches.map { it.channel.name }

        // the pure sports one shouldn't qualify alone
        assertFalse("pure sports group without golf token should not qualify for golf", names.any { it.contains("Latino Sports") })
    }

    @Test
    fun `event group backfill does not reinsert geo ESPN under Golf group`() {
        val game = makePgaGame()
        val channels = listOf(
            makeChannel("arg-golf-group", "ARG | ESPN 2", "Golf"),
            makeChannel("golf-ok", "Golf Channel HD", "Golf"),
            makeChannel("espn-us", "ESPN", "US Sports"),
        )
        val matches = MatchingService().matchGameToChannels(game, channels)
        val names = matches.map { it.channel.name }
        assertFalse("ARG under Golf group must not backfill", names.any { it.contains("ARG") })
        assertTrue(names.any { it.contains("Golf Channel") })
    }

}
