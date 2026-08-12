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
    private var lastScores: Map<String, Triple<Int?, Int?, GameStatus>> = emptyMap()
    private val lastGoalFire = mutableMapOf<String, Long>()
    private val goalCooldownMs = 45_000L

    init {
        ensureChannel()
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
        if (!masterEnabled || favoriteTeamIds.isEmpty() || !canPost()) {
            lastScores = snapshot(games)
            return
        }
        val fav = games.filter { favoriteTeamIds.contains(it.home.id) || favoriteTeamIds.contains(it.away.id) }
        if (notifyGoals) emitGoals(fav)
        if (notifyStarts) emitJustStarted(fav)
        lastScores = snapshot(games)
    }

    private fun snapshot(games: List<Game>) =
        games.associate { it.id to Triple(it.home.score, it.away.score, it.status) }

    private fun emitGoals(fav: List<Game>) {
        val now = System.currentTimeMillis()
        for (g in fav) {
            if (!g.isLive) continue
            val prev = lastScores[g.id] ?: continue
            val h = g.home.score ?: 0
            val a = g.away.score ?: 0
            val ph = prev.first ?: 0
            val pa = prev.second ?: 0
            if (h == ph && a == pa) continue
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
            if (prev.third == GameStatus.LIVE) continue
            if (prev.third == GameStatus.UPCOMING || prev.third == GameStatus.UNKNOWN) {
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
}
