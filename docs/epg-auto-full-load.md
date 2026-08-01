# Automatic full-playlist EPG (IPTV-app parity)

## Product rule
Users never tap to “fill” EPG. Bulk XMLTV + progressive short-EPG run on bootstrap and after playlist load. Guide only shows status.

## Pipeline
1. **Disk cache** paint (instant)
2. **Bulk XMLTV** download → SAX parse (**all** channel ids in time window — no interest-key drop)
3. **Map** to playlist (epg id / tvg / stream id / slug / name)
4. **Progressive short-EPG** for every still-missing Xtream stream, merging into UI each wave
5. Persist cache; background gap-fill if cache warm but incomplete

## What helps next (for Samir / future)
| Help | Why |
|------|-----|
| **Provider type** (Xtream vs M3U) | Short-EPG is Xtream-only; M3U needs a working XMLTV URL |
| **XMLTV URL** if M3U | Some playlists omit `url-tvg` |
| **Approx channel count** | Tunes concurrency / timeouts |
| **Sample of one empty channel** name + whether `epg_channel_id` is set in playlist | Proves provider gap vs map bug |
| **Settings → Guide X/Y** after first full load | Confirms coverage |
| Device logs around “Guide mapped · A/B” | Map quality vs short-fill |

Secrets never leave the device / never paste passwords into chat.

## Xtream bulk guide URL (confirmed)

SportsDash builds the same endpoint panels expose for “M3U EPG”:

```
https://{host}/xmltv.php?username={user}&password={pass}
https://{host}/xmltv.php?username={user}&password={pass}&type=m3u_plus
```

Example host style: `https://your-xtream-host.com/xmltv.php?username=…&password=…`

Also derived when the playlist is saved as M3U `get.php?username=&password=` on the same host.
HTTPS is preferred; HTTP is tried as fallback.

Never log or commit real username/password.
