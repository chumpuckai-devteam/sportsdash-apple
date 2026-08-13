package com.samirpatel.sportsdash.core.notifications

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.samirpatel.sportsdash.core.sports.Game
import com.samirpatel.sportsdash.core.sports.GameStatus

/**
 * Local notifications for favorite-team game starts and score changes.
 * Driven by scores poll (no push server).
 */
class GameNotificationHelper(private val context: Context) {
    private val channelId = "sportsdash_games"
    private var lastScores: Map<String, ScoreSnap> = emptyMap()
    private val lastGoalFire = mutableMapOf<String, Long>()
    private val goalCooldownMs = 45_000L

    init {
        ensureChannel()
    }

    private val scoresPrefs = context.getSharedPreferences("last_game_scores", Context.MODE_PRIVATE)
    private val scoresKey = "snapshots_v1"

    private data class ScoreSnap(
        val home: Int?,
        val away: Int?,
        val status: GameStatus,
        val updatedAt: Long = System.currentTimeMillis()
    )

    private fun loadPersistedLastScores(): Map<String, ScoreSnap> {
        val raw = scoresPrefs.getString(scoresKey, null) ?: return emptyMap()
        return try {
            val obj = org.json.JSONObject(raw)
            val res = mutableMapOf<String, ScoreSnap>()
            val it = obj.keys()
            val cutoff = System.currentTimeMillis() - 48L * 3600 * 1000
            while (it.hasNext()) {
                val id = it.next()
                val o = obj.getJSONObject(id)
                val h = if (o.has("h") && !o.isNull("h")) o.optInt("h") else null
                val a = if (o.has("a") && !o.isNull("a")) o.optInt("a") else null
                val stStr = o.optString("s", "UNKNOWN")
                val st = try { GameStatus.valueOf(stStr) } catch (_: Exception) { GameStatus.UNKNOWN }
                val ts = if (o.has("t") && !o.isNull("t")) o.optLong("t") else System.currentTimeMillis()
                if (ts < cutoff) continue
                res[id] = ScoreSnap(h, a, st, ts)
            }
            res
        } catch (_: Exception) { emptyMap() }
    }

    private fun persistLastScores(snaps: Map<String, ScoreSnap>) {
        try {
            val obj = org.json.JSONObject()
            snaps.forEach { (id, t) ->
                val o = org.json.JSONObject()
                o.put("h", t.home)
                o.put("a", t.away)
                o.put("s", t.status.name)
                o.put("t", t.updatedAt)
                obj.put(id, o)
            }
            scoresPrefs.edit().putString(scoresKey, obj.toString()).commit()
        } catch (_: Exception) {}
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < 26) return
        val mgr = context.getSystemService(NotificationManager::class.java) ?: return
        val ch = NotificationChannel(
            channelId,
            "Game alerts",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "Favorite team game starts and goals"
        }
        mgr.createNotificationChannel(ch)
    }

    fun canPost(): Boolean {
        if (Build.VERSION.SDK_INT >= 33) {
            val ok = ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
            if (!ok) return false
        }
        return NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    fun process(
        games: List<Game>,
        favoriteTeamIds: Set<String>,
        masterEnabled: Boolean,
        notifyStarts: Boolean,
        notifyGoals: Boolean,
    ) {
        if (!masterEnabled) {
            lastScores = emptyMap()
            scoresPrefs.edit().remove(scoresKey).commit()
            return
        }
        if (favoriteTeamIds.isEmpty()) {
            // do not wipe all baselines
            return
        }

        // Seed from disk for cold start / process death catch-up before emitting
        // IMPORTANT: always seed/merge baselines even if !canPost (M1) so when permission granted baselines are current; only skip delivery
        var currLast = lastScores
        if (currLast.isEmpty()) {
            currLast = loadPersistedLastScores()
        } else {
            val disk = loadPersistedLastScores()
            currLast = mergeSnapshots(currLast, disk.filterKeys { !currLast.containsKey(it) })
        }
        lastScores = currLast

        val fav = games.filter { favoriteTeamIds.contains(it.home.id) || favoriteTeamIds.contains(it.away.id) }
        if (canPost()) {
            if (notifyGoals) emitGoals(fav)
            if (notifyStarts) emitJustStarted(fav)
        }
        // merge not full replace - do this regardless of canPost
        lastScores = mergeSnapshots(lastScores, snapshot(games))
        // prune runtime
        val now = System.currentTimeMillis()
        val c48 = now - 48L * 3600 * 1000
        val c6 = now - 6L * 3600 * 1000
        lastScores = lastScores.filter { (_, snap) ->
            if (snap.updatedAt < c48) false
            else if (snap.status == GameStatus.FINAL && snap.updatedAt < c6) false
            else true
        }
        persistLastScores(lastScores)
    }

    private fun snapshot(games: List<Game>) =
        games.associate { it.id to ScoreSnap(it.home.score, it.away.score, it.status) }

    private fun mergeSnapshots(
        existing: Map<String, ScoreSnap>,
        observed: Map<String, ScoreSnap>
    ): Map<String, ScoreSnap> {
        val result = existing.toMutableMap()
        for ((id, snap) in observed) {
            result[id] = snap
        }
        return result
    }

    private fun emitGoals(fav: List<Game>) {
        val now = System.currentTimeMillis()
        for (g in fav) {
            if (!g.isLive) continue
            val prev = lastScores[g.id] ?: continue
            val h = g.home.score ?: 0
            val a = g.away.score ?: 0
            val ph = prev.home ?: 0
            val pa = prev.away ?: 0
            if (!Companion.didScoreIncrease(h, a, ph, pa)) continue
            val last = lastGoalFire[g.id] ?: 0L
            if (now - last < goalCooldownMs) continue
            lastGoalFire[g.id] = now
            val scorer = when {
                h > ph -> g.home.rowLabel
                a > pa -> g.away.rowLabel
                else -> "Score update"
            }
            notify(
                id = ("goal-" + g.id).hashCode(),
                title = "GOAL · ${g.matchupLabel}",
                body = "$scorer · ${g.away.abbreviation} $a–$h ${g.home.abbreviation}",
            )
        }
    }

    private fun emitJustStarted(fav: List<Game>) {
        for (g in fav) {
            if (!g.isLive) continue
            val prev = lastScores[g.id] ?: continue
            if (prev.status == GameStatus.LIVE) continue
            if (prev.status == GameStatus.UPCOMING || prev.status == GameStatus.UNKNOWN) {
                notify(
                    id = ("start-" + g.id).hashCode(),
                    title = "Game started",
                    body = "${g.matchupLabel} is live · ${g.statusLine}",
                )
            }
        }
    }

    private fun notify(id: Int, title: String, body: String) {
        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
        try {
            NotificationManagerCompat.from(context).notify(id, builder.build())
        } catch (_: SecurityException) {
            // missing POST_NOTIFICATIONS
        }
    }

    companion object {
        fun didScoreIncrease(currH: Int?, currA: Int?, prevH: Int?, prevA: Int?): Boolean {
            val h = currH ?: 0
            val a = currA ?: 0
            return h > (prevH ?: 0) || a > (prevA ?: 0)
        }

        /**
         * Pure testable helper (no side effects, JVM only) for the Settings permission callback result.
         * Called with the result of RequestPermission.
         * - Pre-13 (sdkInt < 33): always enable (request not required).
         * - 13+: return granted (denial -> false, keep master off; grant -> enable).
         */
        fun resolveNotificationEnabledFromPermissionResult(sdkInt: Int, permissionGranted: Boolean): Boolean {
            if (sdkInt < 33) return true
            return permissionGranted
        }
    }

    // Public hook for immediate clear on master toggle off (B3)
    fun clearBaselines() {
        lastScores = emptyMap()
        scoresPrefs.edit().remove(scoresKey).commit()
    }
}
