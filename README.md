# ChibiAudio

**Free** personal iOS music player — a fork of [j23n/localmusic](https://github.com/j23n/localmusic) (MPL-2.0), not a greenfield app.

LocalMusic’s architecture is intact under `LocalMusic/` (folder picker, bookmarks, scan, AVPlayer queue, lyrics, lock screen). ChibiAudio adds branding, USB DAC / THX Onyx focus, multi-source playlists, Plex, free radio, and EQ.

See [NOTICE](NOTICE) for upstream attribution.

## Sources matrix

| Source | Free? | Status |
|---|---|---|
| **On My iPhone / app Documents** (Files folder picker + security-scoped bookmarks) | Yes | Core (upstream) |
| **iCloud Drive** folders via Files | Yes | Core — pick folder, bookmark, re-scan; download-to-play when ubiquitous |
| **Google Drive** folders via Files provider | Yes | Same picker — install Google Drive, enable under Files → Browse |
| **App-owned mixed playlists** (local + Plex + radio in one list) | Yes | Free — no subscription to mix *our* playlist DB |
| **Free internet radio** (Icecast/Shoutcast URL + curated SomaFM-style list) | Yes | Radio tab |
| **Plex Media Server** (your music library, token auth, LAN stream) | Yes* | Settings → Plex — *basic local stream; some remote/Plexamp features may need Plex Pass |
| **Apple Music catalog** | Needs **Apple Music** sub to *play* catalog | Optional later (`MusicSubscription.canPlayCatalogContent`); not free streaming |
| Spotify / YouTube Music–style catalogs | Not free for third-party players | Out of free v1 |

### Research lock (licensing honesty)

- **App-owned mixed playlists = free.** Offline + Plex + radio in ChibiAudio’s playlist store needs no sub.
- **Apple Music catalog play** requires the user’s Apple Music subscription. Without it: library/purchased only; catalog rows show “needs Apple Music.” MusicKit can ship; playback is gated.
- **Plex personal music:** PMS + basic stream of *your* library works for local/LAN use without Plex Pass. Document remote/Pass caveats.
- **No IAP / paywall** in free v1. Subscription catalogs stay optional later.

## Hardware — THX Onyx (reference DAC)

Erick’s DAC: **THX Onyx Portable Headphone Amplifier**

- Chip: ESS **ES9281PRO**
- THX AAA amp
- **MQA Renderer** (hardware final unfold — not a full software MQA decoder)
- **DSD** support
- USB for iPhone / PC

### What free ChibiAudio does

1. Detects external **USB audio** route; UI labels **“THX Onyx / USB DAC”** (or the port name if it already says Onyx/THX).
2. **PCM:** prefers bit-perfect; sets `AVAudioSession` preferred sample rate from the track or up to ~192 kHz — **does not crush to 48 kHz**. Actual rate is whatever iOS + Onyx negotiate (`current` / `preferred` shown in Settings & Now Playing).
3. **DSD (.dsf/.dff):** prefers **DoP** over USB when native DSD isn’t available via AVFoundation. DoP encoder is **not** shipped in free v1 yet — we **refuse** silent lossy fall-back (never destroy to low-rate MP3).
4. **MQA:** passthrough / renderer-friendly to the Onyx. **No licensed MQA Core software decoder** in free ChibiAudio.
5. Settings **Hi-res / DAC mode** — maximize preferred rate; **forces EQ off** for a cleaner path to the Onyx.

## Paid-app parity (what’s free here vs needs a sub)

| Capability | ChibiAudio free |
|---|---|
| Offline folders, cloud folder libs (iCloud/Drive), lossless native PCM, lyrics, lock screen | Yes |
| USB DAC hi-res path (THX Onyx) | Yes (PCM; DSD DoP pending) |
| Mixed playlists, free radio, personal Plex | Yes |
| Apple Music *catalog* streaming | Needs Apple Music sub (optional later) |

## Build

```bash
brew install xcodegen   # if needed
xcodegen
open LocalMusic.xcodeproj
```

- Xcode 16+, iOS 18+, Swift 6
- Set your Team under Signing & Capabilities (team ID field is left empty in project.yml on purpose)
- Bundle ID: `com.chibitek.ChibiAudio` · Display name: **ChibiAudio**
- Module/target remains `LocalMusic` so upstream structure stays recognizable

### Plex token setup

1. Sign in at [plex.tv](https://www.plex.tv) → account → authorize devices / XML for `X-Plex-Token`, or use your server’s settings.
2. Settings → Plex → server URL like `http://192.168.x.x:32400` + token → Save → Browse Plex Music.
3. Prefer LAN. `NSAllowsLocalNetworking` is enabled for local HTTP PMS.

### Google Drive / iCloud

1. Install the provider app (Drive) if needed → Files → Browse → enable under More Locations.
2. In ChibiAudio: choose folder via the system document picker.
3. Re-scan after adding files; cloud placeholders download-to-play when possible.

## Architecture (still localmusic)

| Module | Role |
|---|---|
| `LocalMusicApp` | Tabs: Library, Now Playing, Playlists, Radio |
| `AudioPlayerManager` | AVPlayer queue, remote commands, DAC session, cloud prep |
| `CodecRouter` / `DACSession` / `DSDRouter` | Format matrix + THX Onyx USB path |
| `EqualizerController` | 10-band EQ; forced off in DAC bit-perfect mode |
| `Playlist` + `PlaylistSourceRef` | Multi-source entries (file / stream / Plex / Apple Music stub) |
| `AppPlaylistStore` | App-owned JSON playlists in Documents |
| `PlexClient` | PMS sections + direct/stream URLs |
| `RadioCatalog` | Curated + user Icecast URLs |
| `MetadataLoader` / `PersistenceManager` / lyrics / artwork | Upstream |

## Changelog vs upstream localmusic

- Rebrand display name / bundle to ChibiAudio; NOTICE + upstream credit
- CodecRouter format matrix; CloudFileAccess download-to-play
- THX Onyx–oriented DAC mode, route UI, MQA/DSD policy
- Unified multi-source playlists (app-owned JSON + m3u http URLs)
- Free Radio tab; Plex browse/stream; graphic EQ (bit-perfect aware)
- README sources matrix + research lock + hardware section

## License

[MPL-2.0](LICENSE) — same as upstream LocalMusic.
