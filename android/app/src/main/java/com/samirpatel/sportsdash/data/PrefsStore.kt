package com.samirpatel.sportsdash.data

import android.content.Context
import android.util.Log
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.samirpatel.sportsdash.core.model.IptvChannel
import com.samirpatel.sportsdash.core.model.PlaylistConfig
import com.samirpatel.sportsdash.core.model.PlaylistType
import java.io.File
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import org.json.JSONArray
import org.json.JSONObject

private val Context.dataStore by preferencesDataStore(name = "sportsdash_prefs")

/**
 * App prefs. Playlist credentials are multi-written for APK-update resilience:
 * 1) DataStore (primary)
 * 2) SharedPreferences backup (`sportsdash_secure_backup`)
 * 3) filesDir JSON backup (atomic rewrite)
 *
 * Scores ticker is dual-written to SharedPreferences as well (FB.11).
 * All live in app private storage — kept across APK updates (same applicationId).
 * Uninstall still wipes them.
 */
class PrefsStore(private val context: Context) {
    private val keyPlaylist = stringPreferencesKey("playlist_json")
    private val keyShowTicker = booleanPreferencesKey("player_show_scores_ticker")
    private val keyTickerMode = stringPreferencesKey("player_scores_ticker_mode")
    private val keyFavoriteChannels = stringPreferencesKey("favorite_channel_ids_json")
    private val keyFavoriteTeams = stringPreferencesKey("favorite_team_ids_json")
    private val keyFavoriteTeamsMeta = stringPreferencesKey("favorite_teams_meta_json")
    private val keyCleanNames = booleanPreferencesKey("clean_up_channel_names")
    private val keyMoviesNow = booleanPreferencesKey("guide_movies_now")
    private val keyNotifications = booleanPreferencesKey("notify_enabled")
    private val keyNotifyStarts = booleanPreferencesKey("notify_game_starts")
    private val keyNotifyGoals = booleanPreferencesKey("notify_goals")
    private val keyChannelCache = stringPreferencesKey("channel_cache_json")
    private val keyCategoryOrder = stringPreferencesKey("category_order_json")
    private val keyOmdb = stringPreferencesKey("omdb_api_key")
    private val keyTmdb = stringPreferencesKey("tmdb_api_key")
    private val keySelectedLeagues = stringPreferencesKey("selected_league_ids_json")

    private val backupPrefs by lazy {
        context.getSharedPreferences(BACKUP_PREFS, Context.MODE_PRIVATE)
    }

    private val playlistBackupFile: File
        get() = File(context.filesDir, PLAYLIST_BACKUP_NAME)

    val playlistFlow: Flow<PlaylistConfig?> = context.dataStore.data.map { prefs ->
        // Read-only — never edit() inside DataStore collectors (deadlock risk).
        resolvePlaylistReadOnly(prefs[keyPlaylist])
    }.distinctUntilChanged()

    val scoresTickerModeFlow: Flow<com.samirpatel.sportsdash.core.player.ScoresTickerMode> =
        context.dataStore.data.map { prefs ->
            val raw = prefs[keyTickerMode]
                ?: backupPrefs.getString(BACKUP_TICKER_MODE_KEY, null)
            val legacy = prefs[keyShowTicker]
                ?: backupPrefs.getBoolean(BACKUP_TICKER_KEY, true).takeIf {
                    backupPrefs.contains(BACKUP_TICKER_KEY)
                }
            com.samirpatel.sportsdash.core.player.ScoresTickerMode.fromStorage(raw, legacy)
        }

    /** @deprecated use scoresTickerModeFlow */
    val showScoresTickerFlow: Flow<Boolean> = scoresTickerModeFlow.map {
        it != com.samirpatel.sportsdash.core.player.ScoresTickerMode.OFF
    }

    val favoriteChannelIdsFlow: Flow<Set<String>> = context.dataStore.data.map { prefs ->
        decodeIdSet(prefs[keyFavoriteChannels])
    }

    val favoriteTeamIdsFlow: Flow<Set<String>> = context.dataStore.data.map { prefs ->
        val meta = decodeFavoriteTeams(prefs[keyFavoriteTeamsMeta])
        if (meta.isNotEmpty()) meta.map { it.id }.toSet()
        else decodeIdSet(prefs[keyFavoriteTeams])
    }

    /** Full team rows (logo/name) for the favorite rail + picker. */
    val favoriteTeamsFlow: Flow<List<com.samirpatel.sportsdash.core.sports.TeamInfo>> =
        context.dataStore.data.map { prefs ->
            val meta = decodeFavoriteTeams(prefs[keyFavoriteTeamsMeta])
            if (meta.isNotEmpty()) meta
            else {
                // Legacy ids-only → empty details until user re-stars via picker
                emptyList()
            }
        }

    val notificationsEnabledFlow: Flow<Boolean> = context.dataStore.data.map { it[keyNotifications] ?: false }
    val notifyGameStartsFlow: Flow<Boolean> = context.dataStore.data.map { it[keyNotifyStarts] ?: true }
    val notifyGoalsFlow: Flow<Boolean> = context.dataStore.data.map { it[keyNotifyGoals] ?: true }

    val cleanUpNamesFlow: Flow<Boolean> = context.dataStore.data.map { prefs ->
        prefs[keyCleanNames] ?: true
    }

    val moviesNowFlow: Flow<Boolean> = context.dataStore.data.map { prefs ->
        prefs[keyMoviesNow] ?: false
    }

    val omdbKeyFlow: Flow<String?> = context.dataStore.data.map { prefs ->
        prefs[keyOmdb]?.takeIf { it.isNotBlank() }
    }

    val tmdbKeyFlow: Flow<String?> = context.dataStore.data.map { prefs ->
        prefs[keyTmdb]?.takeIf { it.isNotBlank() }
    }

    val selectedLeagueIdsFlow: Flow<Set<String>> = context.dataStore.data.map { prefs ->
        decodeIdSet(prefs[keySelectedLeagues])
    }

    suspend fun savePlaylist(config: PlaylistConfig) {
        val encoded = encodePlaylist(config)
        context.dataStore.edit { it[keyPlaylist] = encoded }
        writePlaylistBackups(encoded)
    }

    /** One-shot read for cold start before flows emit. */
    suspend fun peekPlaylist(): PlaylistConfig? {
        reconcilePlaylistBackup()
        val raw = context.dataStore.data.first()[keyPlaylist]
        return resolvePlaylistReadOnly(raw)
    }

    suspend fun clearPlaylist() {
        context.dataStore.edit {
            it.remove(keyPlaylist)
            it.remove(keyChannelCache)
            it.remove(keyCategoryOrder)
        }
        runCatching {
            backupPrefs.edit().remove(BACKUP_PLAYLIST_KEY).apply()
            if (playlistBackupFile.exists()) playlistBackupFile.delete()
        }.onFailure { Log.w(TAG, "Failed to clear playlist backups", it) }
    }

    suspend fun setScoresTickerMode(mode: com.samirpatel.sportsdash.core.player.ScoresTickerMode) {
        val name = mode.name
        val spOk = backupPrefs.edit()
            .putString(BACKUP_TICKER_MODE_KEY, name)
            .putBoolean(BACKUP_TICKER_KEY, mode != com.samirpatel.sportsdash.core.player.ScoresTickerMode.OFF)
            .commit()
        if (!spOk) Log.w(TAG, "SP commit failed ticker_mode=$name")
        context.dataStore.edit {
            it[keyTickerMode] = name
            it[keyShowTicker] = mode != com.samirpatel.sportsdash.core.player.ScoresTickerMode.OFF
        }
        Log.d(TAG, "setScoresTickerMode mode=$name spOk=$spOk")
    }

    suspend fun setShowScoresTicker(show: Boolean) {
        setScoresTickerMode(
            if (show) com.samirpatel.sportsdash.core.player.ScoresTickerMode.FADE
            else com.samirpatel.sportsdash.core.player.ScoresTickerMode.OFF,
        )
    }

    suspend fun peekScoresTickerMode(): com.samirpatel.sportsdash.core.player.ScoresTickerMode {
        val prefs = runCatching { context.dataStore.data.first() }.getOrNull()
        val raw = prefs?.get(keyTickerMode) ?: backupPrefs.getString(BACKUP_TICKER_MODE_KEY, null)
        val legacy = prefs?.get(keyShowTicker)
            ?: backupPrefs.getBoolean(BACKUP_TICKER_KEY, true).takeIf {
                backupPrefs.contains(BACKUP_TICKER_KEY)
            }
        return com.samirpatel.sportsdash.core.player.ScoresTickerMode.fromStorage(raw, legacy)
    }

    suspend fun peekShowScoresTicker(): Boolean =
        peekScoresTickerMode() != com.samirpatel.sportsdash.core.player.ScoresTickerMode.OFF

    suspend fun setFavoriteChannelIds(ids: Set<String>) {
        context.dataStore.edit {
            it[keyFavoriteChannels] = JSONArray(ids.toList()).toString()
        }
    }

    suspend fun setFavoriteTeamIds(ids: Set<String>) {
        context.dataStore.edit {
            it[keyFavoriteTeams] = JSONArray(ids.toList()).toString()
        }
    }

    suspend fun setFavoriteTeams(teams: List<com.samirpatel.sportsdash.core.sports.TeamInfo>) {
        val distinct = teams
            .filter { it.id.isNotBlank() }
            .distinctBy { it.id }
        context.dataStore.edit { prefs ->
            prefs[keyFavoriteTeamsMeta] = encodeFavoriteTeams(distinct)
            prefs[keyFavoriteTeams] = encodeIdSet(distinct.map { it.id }.toSet())
        }
    }

    suspend fun setNotificationsEnabled(v: Boolean) {
        context.dataStore.edit { it[keyNotifications] = v }
    }
    suspend fun setNotifyGameStarts(v: Boolean) {
        context.dataStore.edit { it[keyNotifyStarts] = v }
    }
    suspend fun setNotifyGoals(v: Boolean) {
        context.dataStore.edit { it[keyNotifyGoals] = v }
    }

    suspend fun setCleanUpNames(enabled: Boolean) {
        context.dataStore.edit { it[keyCleanNames] = enabled }
    }

    suspend fun setMoviesNow(enabled: Boolean) {
        context.dataStore.edit { it[keyMoviesNow] = enabled }
    }

    suspend fun setOmdbKey(key: String) {
        context.dataStore.edit {
            if (key.isBlank()) it.remove(keyOmdb) else it[keyOmdb] = key.trim()
        }
    }

    suspend fun setTmdbKey(key: String) {
        context.dataStore.edit {
            if (key.isBlank()) it.remove(keyTmdb) else it[keyTmdb] = key.trim()
        }
    }

    suspend fun setSelectedLeagueIds(ids: Set<String>) {
        context.dataStore.edit {
            it[keySelectedLeagues] = encodeIdSet(ids)
        }
    }

    /** One-shot read for cold start. Returns null if key absent (missing pref -> caller applies defaults);
     * returns the set (possibly empty) if key present so intentional empty survives restart. */
    suspend fun peekSelectedLeagueIds(): Set<String>? {
        val prefs = runCatching { context.dataStore.data.first() }.getOrNull()
        val raw = prefs?.get(keySelectedLeagues)
        return if (raw == null) null else decodeIdSet(raw)
    }

    suspend fun saveChannelCache(channels: List<IptvChannel>, categoryOrder: List<String>) {
        context.dataStore.edit { prefs ->
            val arr = JSONArray()
            for (ch in channels.take(20_000)) {
                arr.put(
                    JSONObject().apply {
                        put("id", ch.id)
                        put("name", ch.name)
                        put("url", ch.url)
                        put("group", ch.group)
                        put("logo", ch.logo)
                        put("epgChannelId", ch.epgChannelId)
                        put("streamId", ch.streamId)
                    },
                )
            }
            prefs[keyChannelCache] = arr.toString()
            prefs[keyCategoryOrder] = JSONArray(categoryOrder).toString()
        }
    }

    suspend fun getChannelCache(): Pair<List<IptvChannel>, List<String>>? {
        val prefs = context.dataStore.data.first()
        val raw = prefs[keyChannelCache] ?: return null
        val channels = runCatching {
            val arr = JSONArray(raw)
            buildList {
                for (i in 0 until arr.length()) {
                    val o = arr.optJSONObject(i) ?: continue
                    add(
                        IptvChannel(
                            id = o.optString("id"),
                            name = o.optString("name"),
                            url = o.optString("url"),
                            group = o.optString("group").takeIf { it.isNotBlank() },
                            logo = o.optString("logo").takeIf { it.isNotBlank() },
                            epgChannelId = o.optString("epgChannelId").takeIf { it.isNotBlank() },
                            streamId = o.optString("streamId").takeIf { it.isNotBlank() },
                        ),
                    )
                }
            }
        }.getOrNull() ?: return null
        if (channels.isEmpty()) return null
        val cats = decodeStringList(prefs[keyCategoryOrder])
        return channels to cats
    }

    /**
     * Heal DataStore from backups when primary is empty/unusable; seed backups when healthy.
     * Not safe inside a DataStore flow collector.
     */
    suspend fun reconcilePlaylistBackup() {
        val prefs = context.dataStore.data.first()
        val storeRaw = prefs[keyPlaylist]
        val fromStore = storeRaw?.let { decodePlaylist(it) }
        if (fromStore != null && playlistLooksUsable(fromStore)) {
            writePlaylistBackups(encodePlaylist(fromStore))
            return
        }
        val backupRaw = readAnyPlaylistBackupRaw() ?: return
        val fromBackup = decodePlaylist(backupRaw) ?: return
        if (!playlistLooksUsable(fromBackup)) return
        Log.i(TAG, "Restoring playlist into DataStore from backup")
        context.dataStore.edit { it[keyPlaylist] = backupRaw }
        writePlaylistBackups(backupRaw)
    }

    private fun resolvePlaylistReadOnly(dataStoreRaw: String?): PlaylistConfig? {
        val fromStore = dataStoreRaw?.let { decodePlaylist(it) }
        if (fromStore != null && playlistLooksUsable(fromStore)) return fromStore
        val backupRaw = readAnyPlaylistBackupRaw() ?: return fromStore
        val fromBackup = decodePlaylist(backupRaw) ?: return fromStore
        if (!playlistLooksUsable(fromBackup)) return fromStore
        return fromBackup
    }

    private fun playlistLooksUsable(c: PlaylistConfig): Boolean = when (c.type) {
        PlaylistType.XTREAM ->
            c.host.isNotBlank() && c.username.isNotBlank() && c.password.isNotBlank()
        PlaylistType.M3U -> c.m3uUrl.isNotBlank()
    }

    private fun writePlaylistBackups(encoded: String) {
        // commit() so creds are on disk before process death (apply is fire-and-forget).
        runCatching {
            val ok = backupPrefs.edit().putString(BACKUP_PLAYLIST_KEY, encoded).commit()
            if (!ok) Log.w(TAG, "SP commit failed playlist backup")
        }.onFailure { Log.w(TAG, "Failed SharedPreferences playlist backup", it) }
        runCatching {
            val tmp = File(context.filesDir, "$PLAYLIST_BACKUP_NAME.tmp")
            tmp.writeText(encoded, Charsets.UTF_8)
            if (!tmp.renameTo(playlistBackupFile)) {
                playlistBackupFile.writeText(encoded, Charsets.UTF_8)
                tmp.delete()
            }
        }.onFailure { Log.w(TAG, "Failed filesDir playlist backup", it) }
    }

    private fun readAnyPlaylistBackupRaw(): String? {
        val fromSp = backupPrefs.getString(BACKUP_PLAYLIST_KEY, null)?.takeIf { it.isNotBlank() }
        if (fromSp != null) return fromSp
        return runCatching {
            val file = playlistBackupFile
            if (!file.isFile || file.length() == 0L) return null
            file.readText(Charsets.UTF_8).takeIf { it.isNotBlank() }
        }.onFailure { Log.w(TAG, "Failed reading filesDir playlist backup", it) }.getOrNull()
    }

    private fun decodeStringList(raw: String?): List<String> {
        if (raw.isNullOrBlank()) return emptyList()
        return runCatching {
            val arr = JSONArray(raw)
            buildList {
                for (i in 0 until arr.length()) {
                    val s = arr.optString(i)
                    if (s.isNotBlank()) add(s)
                }
            }
        }.getOrDefault(emptyList())
    }

    private fun encodeIdSet(ids: Set<String>): String = Companion.encodeIdSet(ids)

    private fun decodeIdSet(raw: String?): Set<String> = Companion.decodeIdSet(raw)

    private fun encodePlaylist(c: PlaylistConfig): String = JSONObject().apply {
        put("id", c.id)
        put("name", c.name)
        put("type", c.type.name)
        put("host", c.host)
        put("username", c.username)
        put("password", c.password)
        put("m3uUrl", c.m3uUrl)
    }.toString()

    private fun decodePlaylist(raw: String): PlaylistConfig? = runCatching {
        val o = JSONObject(raw)
        PlaylistConfig(
            id = o.optString("id"),
            name = o.optString("name", "Playlist"),
            type = PlaylistType.valueOf(o.optString("type", "XTREAM")),
            host = o.optString("host"),
            username = o.optString("username"),
            password = o.optString("password"),
            m3uUrl = o.optString("m3uUrl"),
        )
    }.getOrNull()


    private fun encodeFavoriteTeams(teams: List<com.samirpatel.sportsdash.core.sports.TeamInfo>): String {
        val arr = JSONArray()
        for (team in teams) {
            arr.put(
                JSONObject()
                    .put("id", team.id)
                    .put("name", team.name)
                    .put("abbreviation", team.abbreviation)
                    .put("logoUrl", team.logoUrl ?: "")
                    .put("shortName", team.shortName ?: "")
                    .put("colorHex", team.colorHex ?: ""),
            )
        }
        return arr.toString()
    }

    private fun decodeFavoriteTeams(raw: String?): List<com.samirpatel.sportsdash.core.sports.TeamInfo> {
        if (raw.isNullOrBlank()) return emptyList()
        return runCatching {
            val arr = JSONArray(raw)
            buildList {
                for (i in 0 until arr.length()) {
                    val o = arr.optJSONObject(i) ?: continue
                    val id = o.optString("id")
                    if (id.isBlank()) continue
                    add(
                        com.samirpatel.sportsdash.core.sports.TeamInfo(
                            id = id,
                            name = o.optString("name"),
                            abbreviation = o.optString("abbreviation"),
                            logoUrl = o.optString("logoUrl").takeIf { it.isNotBlank() },
                            shortName = o.optString("shortName").takeIf { it.isNotBlank() },
                            colorHex = o.optString("colorHex").takeIf { it.isNotBlank() },
                        ),
                    )
                }
            }
        }.getOrDefault(emptyList())
    }

    companion object {
        private const val TAG = "PrefsStore"
        private const val BACKUP_PREFS = "sportsdash_secure_backup"
        private const val BACKUP_PLAYLIST_KEY = "playlist_json"
        private const val BACKUP_TICKER_KEY = "player_show_scores_ticker"
        private const val BACKUP_TICKER_MODE_KEY = "player_scores_ticker_mode"
        private const val PLAYLIST_BACKUP_NAME = "playlist_config_backup.json"

        internal fun encodeIdSet(ids: Set<String>): String = JSONArray(ids.toList()).toString()

        internal fun decodeIdSet(raw: String?): Set<String> {
            if (raw.isNullOrBlank()) return emptySet()
            return runCatching {
                val arr = JSONArray(raw)
                buildSet {
                    for (i in 0 until arr.length()) {
                        val id = arr.optString(i)
                        if (id.isNotBlank()) add(id)
                    }
                }
            }.getOrDefault(emptySet())
        }

        internal fun effectiveSelectedLeagueIds(stored: Set<String>?): Set<String> =
            if (stored == null) com.samirpatel.sportsdash.core.sports.SportLeague.DEFAULTS.map { it.id }.toSet() else stored
    }
}
