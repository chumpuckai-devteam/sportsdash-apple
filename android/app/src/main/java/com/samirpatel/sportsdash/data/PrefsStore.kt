package com.samirpatel.sportsdash.data

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.samirpatel.sportsdash.core.model.PlaylistConfig
import com.samirpatel.sportsdash.core.model.PlaylistType
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import org.json.JSONArray
import org.json.JSONObject

private val Context.dataStore by preferencesDataStore(name = "sportsdash_prefs")

class PrefsStore(private val context: Context) {
    private val keyPlaylist = stringPreferencesKey("playlist_json")
    private val keyShowTicker = booleanPreferencesKey("player_show_scores_ticker")
    private val keyFavorites = stringPreferencesKey("favorite_channel_ids_json")

    val playlistFlow: Flow<PlaylistConfig?> = context.dataStore.data.map { prefs ->
        prefs[keyPlaylist]?.let { decode(it) }
    }

    /** Default true — matches iOS showScoresStrip = true. */
    val showScoresTickerFlow: Flow<Boolean> = context.dataStore.data.map { prefs ->
        prefs[keyShowTicker] ?: true
    }

    val favoriteChannelIdsFlow: Flow<Set<String>> = context.dataStore.data.map { prefs ->
        decodeIdSet(prefs[keyFavorites])
    }

    suspend fun savePlaylist(config: PlaylistConfig) {
        context.dataStore.edit { it[keyPlaylist] = encode(config) }
    }

    suspend fun clearPlaylist() {
        context.dataStore.edit { it.remove(keyPlaylist) }
    }

    suspend fun setShowScoresTicker(show: Boolean) {
        context.dataStore.edit { it[keyShowTicker] = show }
    }

    suspend fun setFavoriteChannelIds(ids: Set<String>) {
        context.dataStore.edit {
            it[keyFavorites] = JSONArray(ids.toList()).toString()
        }
    }

    private fun decodeIdSet(raw: String?): Set<String> {
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

    private fun encode(c: PlaylistConfig): String = JSONObject().apply {
        put("id", c.id)
        put("name", c.name)
        put("type", c.type.name)
        put("host", c.host)
        put("username", c.username)
        put("password", c.password)
        put("m3uUrl", c.m3uUrl)
    }.toString()

    private fun decode(raw: String): PlaylistConfig? = runCatching {
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
}
