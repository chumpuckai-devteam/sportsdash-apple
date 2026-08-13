package com.samirpatel.sportsdash.core.sports

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Calendar

/**
 * TDD for pure grouping behavior: Upcoming must keep every selected league represented
 * even with zero games ("None scheduled" case), matching Apple parity.
 * Tests are JVM pure, no Android deps.
 */
class ScoreboardGroupingUpcomingTest {

    private fun makeLeague(id: String, label: String = id): SportLeague =
        SportLeague.byId(id)!!.copy(label = label)

    private fun makeGame(
        league: SportLeague,
        upcoming: Boolean = true,
        gameId: String? = null
    ): Game {
        val now = System.currentTimeMillis()
        val start = if (upcoming) now + 3600_000L else now - 3600_000L
        return Game(
            id = gameId ?: "${league.id}-g1",
            league = league,
            home = TeamInfo("h1", "Home", "H"),
            away = TeamInfo("a1", "Away", "A"),
            status = if (upcoming) GameStatus.UPCOMING else GameStatus.LIVE,
            startTimeMs = start,
        )
    }

    @Test
    fun `mergeWithRetainedPrevious retains only for failed leagues on partial`() {
        val mlb = makeLeague("mlb")
        val nfl = makeLeague("nfl")
        val prior = listOf(
            makeGame(mlb, gameId = "mlb-prior"),
            makeGame(nfl, gameId = "nfl-prior")
        )
        val fresh = listOf(makeGame(nfl, gameId = "nfl-fresh"))  // only nfl succeeded
        val failed = setOf(mlb)
        val merged = ScoreboardGrouping.mergeWithRetainedPrevious(fresh, prior, failed)
        assertTrue("prior for failed league retained", merged.any { it.id == "mlb-prior" })
        assertTrue("fresh present", merged.any { it.id == "nfl-fresh" })
        assertFalse("prior for successful league not retained", merged.any { it.id == "nfl-prior" })
    }

    @Test
    fun `mergeWithRetainedPrevious all success no retain`() {
        val mlb = makeLeague("mlb")
        val prior = listOf(makeGame(mlb, gameId = "old"))
        val fresh = listOf(makeGame(mlb, gameId = "new"))
        val merged = ScoreboardGrouping.mergeWithRetainedPrevious(fresh, prior, emptySet())
        assertEquals(1, merged.size)
        assertEquals("new", merged.first().id)
    }

    @Test
    fun `ScoreboardFetchResult flags allFailed vs partial correctly`() {
        val rAllFail = ScoreboardFetchResult(games = emptyList(), successfulBoards = 0, failedBoards = 5, failedLeagues = setOf(makeLeague("mlb")))
        assertTrue("all failed", rAllFail.allBoardsFailed)
        assertFalse("not partial", rAllFail.hasPartialFailures)

        val rPartial = ScoreboardFetchResult(games = listOf(makeGame(makeLeague("nfl"))), successfulBoards = 3, failedBoards = 2, failedLeagues = setOf(makeLeague("mlb")))
        assertFalse("not all failed", rPartial.allBoardsFailed)
        assertTrue("has partial", rPartial.hasPartialFailures)
    }

    @Test
    fun `upcomingSportSections keeps all selected leagues even with no games`() {
        val mlb = makeLeague("mlb", "MLB")
        val nfl = makeLeague("nfl", "NFL")
        val nba = makeLeague("nba", "NBA")
        val allLeagues = listOf(mlb, nfl, nba)
        // Only NBA has an upcoming game in fetched
        val games = listOf(makeGame(nba))

        val selected = setOf("mlb", "nfl", "nba")
        val sections = ScoreboardGrouping.upcomingSportSections(
            games = games,
            selectedLeagueIds = selected,
            favoriteTeamIds = emptySet(),
        )

        // Must have 3 sections, one per selected league (different sports)
        assertEquals(3, sections.size)
        val keys = sections.flatMap { it.leagues.map { l -> l.key } }.toSet()
        assertTrue("mlb shelf present", keys.contains("mlb"))
        assertTrue("nfl shelf present", keys.contains("nfl"))
        assertTrue("nba shelf present", keys.contains("nba"))

        // NBA has game, mlb/nfl have empty
        val mlbShelf = sections.flatMap { it.leagues }.first { it.key == "mlb" }
        assertTrue("mlb has no games for None scheduled", mlbShelf.games.isEmpty())
        val nflShelf = sections.flatMap { it.leagues }.first { it.key == "nfl" }
        assertTrue("nfl empty", nflShelf.games.isEmpty())
        val nbaShelf = sections.flatMap { it.leagues }.first { it.key == "nba" }
        assertEquals(1, nbaShelf.games.size)
    }

    @Test
    fun `upcomingSportSections represents each empty league even under same sport (per-league)`() {
        // Simulate two leagues under same sport (e.g. soccer) both selected and empty in feed
        val epl = makeLeague("epl", "EPL")
        val lal = makeLeague("laliga", "La Liga")
        val games = emptyList<Game>()
        val selected = setOf("epl", "laliga")
        val sections = ScoreboardGrouping.upcomingSportSections(
            games = games,
            selectedLeagueIds = selected,
            favoriteTeamIds = emptySet(),
        )
        // Transformation must keep separate league entries (not collapse to one sport empty only)
        val allLeaguesInSections = sections.flatMap { it.leagues }
        assertEquals(2, allLeaguesInSections.size)
        assertTrue("each empty league represented with empty games list", allLeaguesInSections.all { it.games.isEmpty() })
        assertTrue("epl present", allLeaguesInSections.any { it.key == "epl" })
        assertTrue("laliga present", allLeaguesInSections.any { it.key == "laliga" })
    }

    @Test
    fun `upcomingSportSections for non-upcoming filter does not pad (existing behavior preserved)`() {
        // Note: upcomingSportSections is only for upcoming path; regular uses sportSections
        val mlb = makeLeague("mlb")
        val games = listOf(makeGame(mlb, upcoming = false)) // live
        val sections = ScoreboardGrouping.sportSections(games)
        // No pad in regular
        assertEquals(1, sections.size)
    }

    @Test
    fun `sportSections still skips empty leagues for live or final (no change)`() {
        val mlb = makeLeague("mlb")
        val games = listOf(makeGame(mlb, upcoming = false))
        val sections = ScoreboardGrouping.sportSections(games)
        assertEquals(1, sections.size)
    }

    @Test
    fun `tvScoreRails mixed same-sport one nonempty + one empty produces both league IDs and titles`() {
        // Critical for parity: EPL has games, MLS empty -> both rails must survive with labels
        // Use byId (correct labels from ALL) so groupBy key matches inside upcomingSportSections
        val epl = SportLeague.byId("epl")!!
        val mls = SportLeague.byId("mls")!!
        val eplGame = makeGame(epl)
        val games = listOf(eplGame)
        val selected = setOf("epl", "mls")
        val sections = ScoreboardGrouping.upcomingSportSections(
            games = games,
            selectedLeagueIds = selected,
            favoriteTeamIds = emptySet(),
        )
        val rails = ScoreboardGrouping.tvScoreRails(sections)
        assertEquals("exactly two league rails (per-league, not collapsed)", 2, rails.size)
        val eplRail = rails.firstOrNull { "epl" in it.key }!!
        val mlsRail = rails.firstOrNull { "mls" in it.key }!!
        assertEquals("Premier League", eplRail.title)
        assertEquals("MLS", mlsRail.title)
        assertEquals(1, eplRail.games.size)
        assertEquals(0, mlsRail.games.size)
        assertTrue(
            "both league keys survive",
            rails.any { "epl" in it.key } && rails.any { "mls" in it.key }
        )
    }

    // Pure parse result tests using sample strings (no URL/body leak)
    @Test
    fun `parseScoreboard blank body is failure`() {
        val repo = SportsRepository()
        val nfl = SportLeague.byId("nfl")!!
        val res = runCatching { repo.parseScoreboard("", nfl) }
        assertTrue("blank must fail", res.isFailure)
    }
    @Test
    fun `parseScoreboard missing events is failure`() {
        val repo = SportsRepository()
        val nfl = SportLeague.byId("nfl")!!
        val res = runCatching { repo.parseScoreboard("{}", nfl) }
        assertTrue("missing events fail", res.isFailure)
    }
    @Test
    fun `parseScoreboard valid events empty array success empty`() {
        val repo = SportsRepository()
        val nfl = SportLeague.byId("nfl")!!
        val res = runCatching { repo.parseScoreboard("""{"events":[]}""", nfl) }
        assertTrue(res.isSuccess)
        assertEquals(0, res.getOrNull()!!.size)
    }
    @Test
    fun `parseScoreboard malformed failure`() {
        val repo = SportsRepository()
        val nfl = SportLeague.byId("nfl")!!
        val res = runCatching { repo.parseScoreboard("notjson", nfl) }
        assertTrue("malformed fail", res.isFailure)
    }


    @Test
    fun `warningMessageForFailedLeagues uses sorted short labels`() {
        val mlb = makeLeague("mlb", "MLB")
        val nba = makeLeague("nba", "NBA")
        val nfl = makeLeague("nfl", "NFL")
        val msg = ScoreboardGrouping.warningMessageForFailedLeagues(setOf(nba, mlb, nfl))
        assertEquals("MLB, NBA, NFL could not refresh. Other scores are current.", msg)
        assertNull(ScoreboardGrouping.warningMessageForFailedLeagues(emptySet()))
    }

    @Test
    fun `aggregateResults only fails league on default failure (range fail ignored)`() {
        val mlb = makeLeague("mlb", "MLB")
        val nba = makeLeague("nba", "NBA")
        // mlb default failed (even if range gave games? but here no)
        val rMlb = LeagueFetchResult(league=mlb, games=emptyList(), successfulBoards=0, failedBoards=2, defaultSucceeded=false)
        // nba default ok, but range failed (failedBoards>0 but default true)
        val rNba = LeagueFetchResult(league=nba, games=listOf(makeGame(nba)), successfulBoards=1, failedBoards=1, defaultSucceeded=true)
        val agg = ScoreboardGrouping.aggregateResults(listOf(rMlb, rNba))
        assertTrue(agg.hasPartialFailures)
        assertEquals(setOf(mlb), agg.failedLeagues)
        assertTrue("nba games present", agg.games.any { it.league.id == "nba" })
    }

}
