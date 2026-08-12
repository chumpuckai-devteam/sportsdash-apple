# Android Xtream / M3U login persistence (S-AND.FB.8 + FB.14)

## Friend / tester blurb (copy-paste)

```text
SportsDash Android update:
• Keep the old app installed. Open the new APK and tap Update/Install.
• Do NOT uninstall first — Android wipes your Xtream login if you do.
• Same package every build: com.samirpatel.sportsdash
• After update: Settings should still show host + username; password blank = still saved.
• If install says signature conflict, then uninstall is required and you’ll re-enter login once.
```

Never paste real passwords or full private host URLs into group chats; redact hosts in screenshots when possible.

## Upgrade vs uninstall

| Path | How | Login / channels cache |
|------|-----|------------------------|
| **Install over / upgrade** | Open new APK while app still installed, or `adb install -r …` | **Must persist** (same `applicationId` + higher `versionCode` + same signing key) |
| **Uninstall then install** | Long-press → Uninstall, then install APK | **Wiped** — app private storage is deleted. Dual-write cannot survive this. |

Uninstall wipe is normal Android platform behavior. Export/backup-for-reinstall is **out of scope** unless product explicitly wants it.

## What the app stores (private storage only)

Primary + backups all under the app sandbox (`/data/data/com.samirpatel.sportsdash/…`):

1. **DataStore** `sportsdash_prefs` → `playlist_json`
2. **SharedPreferences** `sportsdash_secure_backup` → `playlist_json` (written with `commit()`)
3. **File** `filesDir/playlist_config_backup.json` (temp + rename)

On cold start, `PrefsStore.peekPlaylist()` / `reconcilePlaylistBackup()` heal DataStore from SP or file backup if the primary is empty/unusable.

Related UI/VM behavior:

- `AppViewModel` peeks playlist before flows settle so Settings is not empty after an update.
- Blank password on Save = keep previously stored password.
- Settings hydrates host/user (not password) from restored playlist.

## Build identity (must stay stable for dogfood)

| Field | Value |
|-------|--------|
| `applicationId` | `com.samirpatel.sportsdash` |
| Signing | Debug keystore for friend APKs (same machine/key → install-over works) |
| `versionCode` | Must **increase** each dogfood ship (see `android/app/build.gradle.kts`) |

If friends build with a **different debug keystore**, Android reports `INSTALL_FAILED_UPDATE_INCOMPATIBLE` and forces uninstall (login lost). Prefer one shared APK from the usual builder.

## Smoke matrix (one device)

1. **Fresh install** — install APK on device with no SportsDash → enter Xtream → channels load → force-stop → reopen → still logged in.
2. **Upgrade install** — with login saved, install newer APK **without** uninstall (`adb install -r` or in-place Update) → Settings still shows host/user; blank password label “saved · leave blank to keep”; channels/EPG reload with saved creds.
3. **Uninstall control** — uninstall → reinstall → Settings empty (expected). Document only; do not “fix” this path without an export feature.

## Code touchpoints

- `android/app/src/main/java/com/samirpatel/sportsdash/data/PrefsStore.kt`
- `android/app/src/main/java/com/samirpatel/sportsdash/AppViewModel.kt` (cold peek + blank password keep)
- `android/app/src/main/java/com/samirpatel/sportsdash/ui/SettingsScreen.kt` (hydrate + labels)
- `android/app/build.gradle.kts` (`applicationId`, `versionCode`)
- `android/README.md` (install-over instructions)

## Out of scope (unless Samir asks)

- User-visible “Backup login” / share credential file
- Android Auto Backup custom rules to survive uninstall
- Keystore/Keychain migration of IPTV passwords

## Security notes for agents

- Never log raw passwords or commit real credentials.
- Redact hosts in public docs and Discord screenshots when possible.
- Dual-write is **resilience within private storage**, not encryption-at-rest beyond app sandbox.
