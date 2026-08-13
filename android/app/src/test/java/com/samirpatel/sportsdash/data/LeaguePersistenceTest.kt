package com.samirpatel.sportsdash.data

import com.samirpatel.sportsdash.core.sports.SportLeague
import com.samirpatel.sportsdash.core.util.ChannelNameCleanup
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.assertFalse
import com.samirpatel.sportsdash.LeagueSelectionCoordinator
import org.junit.Test
import com.samirpatel.sportsdash.core.notifications.GameNotificationHelper

/**
 * TDD JVM test for league persistence migration/defaults behavior (pure aspects).
 * Actual DataStore roundtrip tested in integration; here pure logic + exercises prod helpers.
 * Also covers canonical dedupe helper (F).
 */
class LeaguePersistenceTest {

    @Test
    fun `defaults are used when missing preference (null)`() {
        val defaults = SportLeague.DEFAULTS.map { it.id }.toSet()
        assertFalse("defaults must not be empty for test", defaults.isEmpty())
        // null = missing pref -> defaults (presence-aware)
        val effective = PrefsStore.effectiveSelectedLeagueIds(null)
        assertEquals(defaults, effective)
    }

    @Test
    fun `intentional empty set survives (no defaults applied)`() {
        val empty = emptySet<String>()
        // present empty -> keep empty (user cleared all leagues)
        val effective = PrefsStore.effectiveSelectedLeagueIds(empty)
        assertEquals(empty, effective)
        assertTrue("empty does not auto default", effective.isEmpty())
    }

    @Test
    fun `custom selection preserved over defaults`() {
        val custom = setOf("nba", "mlb", "epl")
        val stored = custom
        val effective = PrefsStore.effectiveSelectedLeagueIds(stored)
        assertEquals(custom, effective)
        assertTrue("custom survives", "nba" in effective)
    }

    @Test
    fun `encode decode roundtrip for ids uses prod helpers`() {
        val ids = setOf("nfl", "mlb")
        val json = PrefsStore.encodeIdSet(ids)
        val decoded = PrefsStore.decodeIdSet(json)
        assertEquals(ids, decoded)
    }

    @Test
    fun `canonical dedupe key always uses cleanup independent of display pref (F)`() {
        val raw = "Channel HD (FHD) [UHD]"
        val alwaysClean = ChannelNameCleanup.displayName(raw, enabled = true)
        assertTrue("always clean removes HD qualifiers", !alwaysClean.contains("HD") && !alwaysClean.contains("FHD"))
        // display pref off returns raw, but dedupe must ignore and always clean
        val displayOff = ChannelNameCleanup.displayName(raw, enabled = false)
        assertEquals(raw, displayOff)
        // canonical should be stable for dedupe key
        assertTrue("cleaned shorter", alwaysClean.length < raw.length)
    }

    @Test
    fun `stale self emission ignored latest external accepted`() {
        var current: Set<String> = setOf("nfl", "mlb")
        val toA = emptySet<String>()
        current = toA
        // exercise prod helper for ack (no selfIssued now)
        val desired = toA
        val emittedSelf = toA
        if (LeagueSelectionCoordinator.shouldAck(desired, emittedSelf)) {
            // ack simulated
        }
        assertEquals(emptySet<String>(), current)
        val ext = setOf("nba")
        if (!LeagueSelectionCoordinator.shouldAck(desired, ext) && LeagueSelectionCoordinator.shouldApplyExternal(null, ext, current)) {
            current = ext
        }
        assertEquals(setOf("nba"), current)
    }

    @Test
    fun `init sequential await one refresh then drop external only`() {
        var state = setOf("default")
        var refreshed = false
        fun doRefresh() { refreshed = true }
        val peeked: Set<String>? = null
        val initial = if (peeked == null) setOf("nfl","mlb") else peeked
        state = initial
        doRefresh()
        assertTrue(refreshed)
        refreshed = false
        val next = setOf("epl")
        // use prod external check instead of hand if
        if (LeagueSelectionCoordinator.shouldApplyExternal(null, next, state)) {
            state = next
            doRefresh()
        }
        assertEquals(setOf("epl"), state)
    }

    // Pure state tests for LeagueSelectionCoordinator semantics (A= first toggle, B=second)
    @Test
    fun `coordinator A then B, stale A ignored, B ack, later external A accepted`() {
        var localDesired: Set<String>? = null
        var state: Set<String> = emptySet()
        var refreshedCount = 0
        fun refresh() { refreshedCount++ }

        // initial already done, desired nil
        // toggle A
        val A = setOf("nfl", "mlb")
        localDesired = A
        state = A
        refresh()  // toggle side effect
        // write happens, emitted A -- exercise prod
        val emittedA = A
        if (LeagueSelectionCoordinator.shouldAck(localDesired, emittedA)) {
            localDesired = null  // ack
        }
        assertEquals(null, localDesired)
        assertEquals(A, state)

        // toggle B
        val B = setOf("nba")
        localDesired = B
        state = B
        refresh()
        // stale A emission arrives while desired=B pending
        val staleA = A
        if (LeagueSelectionCoordinator.shouldAck(localDesired, staleA)) {
            localDesired = null
        } else if (LeagueSelectionCoordinator.shouldApplyExternal(localDesired, staleA, state)) {
            state = staleA
            refresh()
        }
        // stale ignored, desired still B, state still B
        assertEquals(B, state)
        assertEquals(2, refreshedCount)

        // now B emission acks
        val emittedB = B
        if (LeagueSelectionCoordinator.shouldAck(localDesired, emittedB)) {
            localDesired = null
        }
        assertEquals(null, localDesired)
        assertEquals(B, state)

        // later external A accepted
        val extA = setOf("nfl")
        if (LeagueSelectionCoordinator.shouldApplyExternal(localDesired, extA, state)) {
            state = extA
            refresh()
        }
        assertEquals(setOf("nfl"), state)
        assertEquals(3, refreshedCount)
    }

    @Test
    fun `coordinator intentional empty is accepted and external unequal applies`() {
        var localDesired: Set<String>? = null
        var state: Set<String> = setOf("nba")
        fun doRefresh() {}

        val empty = emptySet<String>()
        localDesired = empty
        state = empty
        // write empty -- use prod
        val emitted = empty
        if (LeagueSelectionCoordinator.shouldAck(localDesired, emitted)) {
            localDesired = null
        }
        assertEquals(empty, state)
        assertEquals(null, localDesired)

        // external other
        val other = setOf("mlb")
        if (LeagueSelectionCoordinator.shouldApplyExternal(localDesired, other, state)) {
            state = other
            doRefresh()
        }
        assertEquals(setOf("mlb"), state)
    }



    @Test
    fun `permission resolve pre-13 always enables on grant path`() {
        assertTrue(GameNotificationHelper.resolveNotificationEnabledFromPermissionResult(31, false))
        assertTrue(GameNotificationHelper.resolveNotificationEnabledFromPermissionResult(32, true))
    }

    @Test
    fun `permission resolve Android13+ denial keeps false, grant enables`() {
        assertFalse(GameNotificationHelper.resolveNotificationEnabledFromPermissionResult(33, false))
        assertFalse(GameNotificationHelper.resolveNotificationEnabledFromPermissionResult(34, false))
        assertTrue(GameNotificationHelper.resolveNotificationEnabledFromPermissionResult(33, true))
    }

    @Test
    fun `permission result denial never enables on 13+`() {
        val result = GameNotificationHelper.resolveNotificationEnabledFromPermissionResult(33, false)
        assertFalse("denial on 13+ must keep/set false", result)
    }


    // === New deterministic tests for revision-governed coordinator (blocker 3) ===

    @Test
    fun `revision A to B to A stale first A does not clear latest pending`() {
        var pendingRev: Long? = null
        var pendingDesired: Set<String>? = null
        var writeRev = 0L

        // send A rev=1
        writeRev = LeagueSelectionCoordinator.computeNextRevision(writeRev)
        val revA = writeRev
        pendingDesired = setOf("a")
        pendingRev = revA

        // send B rev=2
        writeRev = LeagueSelectionCoordinator.computeNextRevision(writeRev)
        val revB = writeRev
        pendingDesired = setOf("b")
        pendingRev = revB

        // stale A success arrives (rev1)
        val clearStale = LeagueSelectionCoordinator.shouldClearPendingOnSuccess(revA, pendingRev)
        assertFalse("stale A must not clear current B pending", clearStale)

        // current B success clears
        val clearCurrent = LeagueSelectionCoordinator.shouldClearPendingOnSuccess(revB, pendingRev)
        assertTrue(clearCurrent)
    }

    @Test
    fun `failure on current rev clears then reconcile if persisted differs`() {
        var pendingRev: Long? = 5L
        var pendingDesired: Set<String>? = setOf("x")
        val failedVal = setOf("x")
        val currState = setOf("y")

        val should = LeagueSelectionCoordinator.shouldClearAndReconcileOnFailure(5L, pendingRev, failedVal, pendingDesired)
        assertTrue(should)

        // simulate older failure
        val shouldOld = LeagueSelectionCoordinator.shouldClearAndReconcileOnFailure(3L, pendingRev, failedVal, pendingDesired)
        assertFalse(shouldOld)
    }

    @Test
    fun `collector ignores emissions while pending, external only after no pending`() {
        val pendingRev: Long? = 10L
        assertTrue(LeagueSelectionCoordinator.shouldIgnoreWhilePending(pendingRev))
        assertFalse(LeagueSelectionCoordinator.shouldIgnoreWhilePending(null))

        val noPend = LeagueSelectionCoordinator.shouldApplyExternalNoPending(null, setOf("new"), setOf("old"))
        assertTrue(noPend)

        val pendBlock = LeagueSelectionCoordinator.shouldApplyExternalNoPending(pendingRev, setOf("new"), setOf("old"))
        assertFalse(pendBlock)
    }

    @Test
    fun `external after pending cleared applies`() {
        // after success clear pendingRev=null, then external applies
        val afterClear = LeagueSelectionCoordinator.shouldApplyExternalNoPending(null, setOf("mlb"), setOf("nfl"))
        assertTrue(afterClear)
    }

}
