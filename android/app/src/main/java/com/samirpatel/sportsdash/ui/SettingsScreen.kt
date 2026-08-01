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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.samirpatel.sportsdash.AppUiState
import com.samirpatel.sportsdash.AppViewModel
import com.samirpatel.sportsdash.core.sports.SportLeague
import com.samirpatel.sportsdash.ui.theme.Gold
import com.samirpatel.sportsdash.ui.theme.Muted
import com.samirpatel.sportsdash.ui.theme.Panel
import com.samirpatel.sportsdash.ui.theme.TextPrimary
import com.samirpatel.sportsdash.ui.theme.VoidBlack

@Composable
fun SettingsScreen(vm: AppViewModel, state: AppUiState) {
    var mode by remember { mutableIntStateOf(0) }
    var name by remember { mutableStateOf(state.playlist?.name ?: "My IPTV") }
    var serverUrl by remember { mutableStateOf(state.playlist?.host ?: "") }
    var user by remember { mutableStateOf(state.playlist?.username ?: "") }
    var pass by remember { mutableStateOf("") }
    var m3u by remember { mutableStateOf(state.playlist?.m3uUrl ?: "") }

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
                    label = { Text("Password") },
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
                Text(text = "Active: ${pl.name} · ${pl.type}", color = TextPrimary)
            }
            state.channelStatus?.let { Text(text = it, color = Muted) }
            state.channelError?.let { Text(text = it, color = MaterialTheme.colorScheme.error) }
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
                    "Tabs: Scores · Guide · Settings. https://www.videolan.org/",
                color = Muted,
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }
}
