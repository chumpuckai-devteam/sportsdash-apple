package com.samirpatel.sportsdash.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.samirpatel.sportsdash.AppUiState
import com.samirpatel.sportsdash.AppViewModel
import com.samirpatel.sportsdash.core.model.PlaylistType
import com.samirpatel.sportsdash.core.sports.SportLeague
import com.samirpatel.sportsdash.ui.theme.Gold
import com.samirpatel.sportsdash.ui.theme.Muted
import com.samirpatel.sportsdash.ui.theme.Panel
import com.samirpatel.sportsdash.ui.theme.TextPrimary
import com.samirpatel.sportsdash.ui.theme.VoidBlack

@Composable
fun SettingsScreen(vm: AppViewModel, state: AppUiState) {
    val notifPermission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { /* state flows from system */ }
    var mode by remember { mutableIntStateOf(0) }
    var name by remember { mutableStateOf("My IPTV") }
    var serverUrl by remember { mutableStateOf("") }
    var user by remember { mutableStateOf("") }
    var pass by remember { mutableStateOf("") }
    var m3u by remember { mutableStateOf("") }
    // Stable key for last form hydrate (id may be blank on very old saves).
    var hydratedPlaylistKey by remember { mutableStateOf<String?>(null) }

    // When playlist loads from disk (after update / cold start), fill the form once per key.
    // Password stays blank intentionally — blank save keeps existing password.
    LaunchedEffect(state.playlist?.id, state.playlist?.host, state.playlist?.username, state.playlist?.m3uUrl) {
        val pl = state.playlist ?: return@LaunchedEffect
        val key = pl.id.takeIf { it.isNotBlank() }
            ?: "${pl.type.name}|${pl.host}|${pl.username}|${pl.m3uUrl}"
        if (hydratedPlaylistKey == key) return@LaunchedEffect
        name = pl.name.ifBlank { "My IPTV" }
        serverUrl = pl.host
        user = pl.username
        m3u = pl.m3uUrl
        mode = if (pl.type == PlaylistType.M3U) 1 else 0
        pass = ""
        hydratedPlaylistKey = key
    }

    val fields = OutlinedTextFieldDefaults.colors(
        focusedBorderColor = Gold,
        unfocusedBorderColor = Muted,
        focusedLabelColor = Gold,
        unfocusedLabelColor = Muted,
        cursorColor = Gold,
        focusedTextColor = TextPrimary,
        unfocusedTextColor = TextPrimary,
        focusedPlaceholderColor = Muted,
        unfocusedPlaceholderColor = Muted,
    )
    val chips = FilterChipDefaults.filterChipColors(
        selectedContainerColor = Gold,
        selectedLabelColor = VoidBlack,
        containerColor = Panel,
        labelColor = TextPrimary,
    )

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(VoidBlack)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Text(
                text = "Playlist",
                color = Gold,
                style = MaterialTheme.typography.titleMedium,
            )
            Text(
                text = "Paste your Xtream server URL (https://host:port) or full player_api link. " +
                    "libVLC hard engine — same family as iOS.",
                color = Muted,
                style = MaterialTheme.typography.bodySmall,
            )
            Text(
                text = "Updates: install the new APK over this app — do not uninstall first, " +
                    "or Android wipes your login.",
                color = Muted,
                style = MaterialTheme.typography.bodySmall,
            )
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(
                    selected = mode == 0,
                    onClick = { mode = 0 },
                    label = { Text("Xtream") },
                    colors = chips,
                )
                FilterChip(
                    selected = mode == 1,
                    onClick = { mode = 1 },
                    label = { Text("M3U URL") },
                    colors = chips,
                )
            }
        }
        item {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text("Name") },
                modifier = Modifier.fillMaxWidth(),
                colors = fields,
                singleLine = true,
            )
        }
        if (mode == 0) {
            item {
                OutlinedTextField(
                    value = serverUrl,
                    onValueChange = { serverUrl = it },
                    label = { Text("Xtream server URL") },
                    placeholder = { Text("https://your-provider.example") },
                    modifier = Modifier.fillMaxWidth(),
                    colors = fields,
                    singleLine = true,
                )
            }
            item {
                OutlinedTextField(
                    value = user,
                    onValueChange = { user = it },
                    label = { Text("Username") },
                    modifier = Modifier.fillMaxWidth(),
                    colors = fields,
                    singleLine = true,
                )
            }
            item {
                OutlinedTextField(
                    value = pass,
                    onValueChange = { pass = it },
                    label = {
                        Text(
                            if (state.playlist?.type == PlaylistType.XTREAM &&
                                state.playlist!!.password.isNotBlank()
                            ) {
                                "Password (saved · leave blank to keep)"
                            } else {
                                "Password"
                            },
                        )
                    },
                    modifier = Modifier.fillMaxWidth(),
                    colors = fields,
                    singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                )
            }
            item {
                Button(
                    onClick = { vm.saveXtream(name, serverUrl, user, pass) },
                    enabled = serverUrl.isNotBlank() && user.isNotBlank() &&
                        (pass.isNotBlank() || state.playlist?.password?.isNotBlank() == true),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Gold,
                        contentColor = VoidBlack,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Save & load live channels")
                }
            }
        } else {
            item {
                OutlinedTextField(
                    value = m3u,
                    onValueChange = { m3u = it },
                    label = { Text("M3U URL") },
                    placeholder = { Text("https://…/get.php?…") },
                    modifier = Modifier.fillMaxWidth(),
                    colors = fields,
                    singleLine = true,
                )
            }
            item {
                Button(
                    onClick = { vm.saveM3u(name, m3u) },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Gold,
                        contentColor = VoidBlack,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Save & load M3U")
                }
            }
        }
        item {
            state.playlist?.let { pl ->
                val ready = when (pl.type) {
                    PlaylistType.XTREAM ->
                        pl.host.isNotBlank() && pl.username.isNotBlank() && pl.password.isNotBlank()
                    PlaylistType.M3U -> pl.m3uUrl.isNotBlank()
                }
                Text(
                    text = if (ready) {
                        "Saved login: ${pl.name} · ${pl.type} · will keep after app updates"
                    } else {
                        "Active: ${pl.name} · ${pl.type} (incomplete)"
                    },
                    color = TextPrimary,
                )
            }
            state.channelStatus?.let { Text(text = it, color = Muted) }
            state.channelError?.let { Text(text = it, color = MaterialTheme.colorScheme.error) }
            state.epgStatus?.let { Text(text = it, color = Muted) }
        }
        item {
            Button(
                onClick = { vm.reloadEpg(force = true) },
                enabled = state.playlist != null && !state.isLoadingEpg,
                colors = ButtonDefaults.buttonColors(
                    containerColor = Panel,
                    contentColor = Gold,
                ),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(if (state.isLoadingEpg) "Loading EPG…" else "Reload EPG guide")
            }
        }
        item {
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = "Movie ratings (OMDb / TMDB)",
                color = Gold,
                style = MaterialTheme.typography.titleMedium,
            )
            Text(
                text = "Optional. Same keys as iOS General settings. Leave blank to hide chips.",
                color = Muted,
                style = MaterialTheme.typography.bodySmall,
            )
            var omdb by remember { mutableStateOf("") }
            var tmdb by remember { mutableStateOf("") }
            OutlinedTextField(
                value = omdb,
                onValueChange = { omdb = it },
                label = { Text(if (state.omdbKeyPresent) "OMDb key (saved · paste to replace)" else "OMDb API key") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
                colors = fields,
            )
            Button(
                onClick = { vm.setOmdbKey(omdb); omdb = "" },
                colors = ButtonDefaults.buttonColors(containerColor = Panel, contentColor = Gold),
                modifier = Modifier.fillMaxWidth(),
            ) { Text(if (state.omdbKeyPresent) "Update OMDb key" else "Save OMDb key") }
            OutlinedTextField(
                value = tmdb,
                onValueChange = { tmdb = it },
                label = { Text(if (state.tmdbKeyPresent) "TMDB key (saved · paste to replace)" else "TMDB API key") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
                colors = fields,
            )
            Button(
                onClick = { vm.setTmdbKey(tmdb); tmdb = "" },
                colors = ButtonDefaults.buttonColors(containerColor = Panel, contentColor = Gold),
                modifier = Modifier.fillMaxWidth(),
            ) { Text(if (state.tmdbKeyPresent) "Update TMDB key" else "Save TMDB key") }
            Text(
                text = "This product uses the TMDB API but is not endorsed or certified by TMDB.",
                color = Muted,
                style = MaterialTheme.typography.bodySmall,
            )
        }
        item {
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = "Game alerts",
                color = Gold,
                style = MaterialTheme.typography.titleMedium,
            )
            Text(
                text = "Favorite teams only. Alerts when scores refresh (start + goals). No spam server.",
                color = Muted,
                style = MaterialTheme.typography.bodySmall,
            )
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(10.dp))
                    .background(Panel)
                    .clickable {
                        val turningOn = !state.notificationsEnabled
                        if (turningOn && Build.VERSION.SDK_INT >= 33) {
                            notifPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
                        }
                        vm.setNotificationsEnabled(turningOn)
                    }
                    .padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Enable alerts", color = TextPrimary, modifier = Modifier.weight(1f))
                Text(
                    text = if (state.notificationsEnabled) "ON" else "OFF",
                    color = if (state.notificationsEnabled) Gold else Muted,
                    fontWeight = FontWeight.Bold,
                )
            }
            if (state.notificationsEnabled) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(10.dp))
                        .background(Panel)
                        .clickable { vm.setNotifyGameStarts(!state.notifyGameStarts) }
                        .padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("Game starting", color = TextPrimary, modifier = Modifier.weight(1f))
                    Text(
                        text = if (state.notifyGameStarts) "ON" else "OFF",
                        color = if (state.notifyGameStarts) Gold else Muted,
                        fontWeight = FontWeight.Bold,
                    )
                }
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(10.dp))
                        .background(Panel)
                        .clickable { vm.setNotifyGoals(!state.notifyGoals) }
                        .padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("Goals / score changes", color = TextPrimary, modifier = Modifier.weight(1f))
                    Text(
                        text = if (state.notifyGoals) "ON" else "OFF",
                        color = if (state.notifyGoals) Gold else Muted,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
        }
        item {
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = "Display",
                color = Gold,
                style = MaterialTheme.typography.titleMedium,
            )
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(10.dp))
                    .background(Panel)
                    .clickable { vm.setCleanUpNames(!state.cleanUpNames) }
                    .padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "Clean up channel names",
                    color = TextPrimary,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    text = if (state.cleanUpNames) "ON" else "OFF",
                    color = if (state.cleanUpNames) Gold else Muted,
                    fontWeight = FontWeight.Bold,
                )
            }
        }
        item {
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = "Score leagues",
                color = Gold,
                style = MaterialTheme.typography.titleMedium,
            )
            Text(
                text = "Toggle leagues for the Scores dashboard (ESPN).",
                color = Muted,
                style = MaterialTheme.typography.bodySmall,
            )
        }
        items(items = SportLeague.ALL, key = { it.id }) { league ->
            val on = league.id in state.selectedLeagueIds
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(10.dp))
                    .background(if (on) Gold.copy(alpha = 0.15f) else Panel)
                    .clickable { vm.toggleLeague(league.id) }
                    .padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = league.label,
                    color = TextPrimary,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    text = if (on) "ON" else "OFF",
                    color = if (on) Gold else Muted,
                    fontWeight = FontWeight.Bold,
                )
            }
        }
        item {
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                text = "About",
                color = Gold,
                style = MaterialTheme.typography.titleMedium,
            )
            Text(
                text = "SportsDash Android — Scores (ESPN) + IPTV Guide (libVLC / LGPL). " +
                    "Tabs: Scores · Guide · Settings. https://www.videolan.org/\n\n" +
                    "Playlist login is stored on-device (DataStore + private backups) and survives " +
                    "app updates with the same package id. Uninstalling SportsDash clears login " +
                    "and all local data.",
                color = Muted,
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }
}
