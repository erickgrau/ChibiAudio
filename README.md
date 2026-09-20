# ChibiAudio

**Free v1** personal iOS music player — a fork of [j23n/localmusic](https://github.com/j23n/localmusic) (MPL-2.0), not a greenfield app.

LocalMusic architecture stays under `LocalMusic/` (folder picker, security-scoped bookmarks, library scan, AVPlayer queue, lyrics, lock screen / Now Playing). ChibiAudio layers branding and the locked free-v1 extras below.

See [NOTICE](NOTICE) for upstream attribution. No IAP / paywall.

## Free v1 — Soft PASS lock

| Capability | Free v1 |
|---|---|
| Offline On My iPhone / app Documents via Files + security-scoped bookmarks | Yes (upstream) |
| iCloud Drive / Google Drive folders via system Files picker + bookmarks | Yes |
| Lossless / hi-res PCM (FLAC, ALAC, WAV, AIFF, high-bitrate AAC/M4A, MP3) native AVFoundation | Yes |
| DSD (`.dsf`/`.dff`) — DoP preferred; never silent lossy fall-back | Policy yes; DoP encoder not bundled yet (refuse play vs crush) |
| THX Onyx bit-perfect PCM (USB route, Hi-res/DAC mode, EQ bypass) | Yes |
| Cross-source app-owned playlists (local/cloud + Plex + radio; AM IDs gated) | Yes |
| Plex personal library — prefer direct/original stream | Yes (LAN/token) |
| Graphic EQ with presets; **bypassed** when bit-perfect / DAC mode | Yes (settings + bypass; float-PCM engine insert optional follow-up) |
| Embedded + synced lyrics, background audio, lock screen | Yes (upstream) |
| Free internet radio (Icecast/Shoutcast URL + curated list) | Yes |
| Apple Music *catalog* play | Optional / gated — needs user Apple Music sub; not free streaming |
| MQA | Onyx **renderer** passthrough only — **no** licensed MQA Core decoder |
| IAP / paywall | None |

Out of free v1: Spotify / YouTube Music–style catalogs; visual redesign; App Store submit.

## Sources matrix

| Source | Free? | Notes |
|---|---|---|
| On My iPhone / Documents | Yes | Files folder picker + bookmarks; plays fully offline |
| iCloud Drive | Yes | Same picker; download-to-play when ubiquitous |
| Google Drive (Files provider) | Yes | Install Drive app → enable in Files → pick folder |
| App-owned mixed playlists | Yes | No sub to mix offline + Plex + radio in *our* DB |
| Free radio (Icecast / Shoutcast URL) | Yes | Radio tab |
| Plex Media Server (your library) | Yes* | Token + LAN stream; *some remote/Plexamp features may need Plex Pass |
| Apple Music catalog | Sub required to *play* | Optional later; gated on `canPlayCatalogContent` |
| Spotify / YT Music catalogs | No | Out of free v1 |

### Research lock

- App-owned mixed playlists = free.
- Apple Music catalog play needs the user’s Apple Music subscription.
- Plex: basic stream of *your* PMS library on LAN does not require Plex Pass; remote/Pass caveats apply.
- No IAP. No pretending paid catalogs are free.

## Hardware — THX Onyx (reference DAC)

**THX Onyx Portable Headphone Amplifier** — ESS **ES9281PRO**, THX AAA, **MQA Renderer**, DSD, USB.

1. Detect USB audio; label **THX Onyx / USB DAC** (or port name if it already says Onyx/THX).
2. **PCM:** bit-perfect intent; preferred sample rate from track or up to ~192 kHz — **no 48 kHz crush**. Show negotiated rate in Settings / Now Playing.
3. **DSD:** DoP over USB preferred; free v1 refuses silent MP3/AAC fall-back if DoP isn’t available yet.
4. **MQA:** hardware renderer on the Onyx only — no licensed software MQA Core decode.
5. **Hi-res / DAC mode** maximizes preferred rate and **forces EQ off**.

## Build

```bash
brew install xcodegen   # if needed
xcodegen
open LocalMusic.xcodeproj
```

- Xcode 16+, iOS 18+, Swift 6
- Set your Team under Signing & Capabilities (team ID left empty in `project.yml` on purpose)
- Bundle ID: `com.chibitek.ChibiAudio` · Display name: **ChibiAudio**
- Xcode target/module name remains `LocalMusic` (upstream layout)

### Plex token

1. Obtain `X-Plex-Token` from your Plex account / server.
2. Settings → Plex → `http://…:32400` + token → Browse Plex Music.
3. Prefer LAN (`NSAllowsLocalNetworking` enabled).

### Google Drive / iCloud

1. Enable the provider under Files → Browse.
2. ChibiAudio → choose folder via document picker.
3. Re-scan after adding files; cloud placeholders download-to-play when possible.

## Architecture (still localmusic)

| Module | Role |
|---|---|
| `LocalMusicApp` | Tabs: Home (default), Library, Now Playing, Playlists, Radio |
| `RecentsStore` | Minimal play history for Home Recent / Continue |
| `AudioPlayerManager` | AVPlayer queue, remote commands, DAC session, cloud prep |
| `CodecRouter` / `DACSession` / `DSDRouter` | Format matrix + THX Onyx USB path |
| `EqualizerController` | 10-band EQ + presets; forced off in DAC bit-perfect mode |
| `Playlist` + `PlaylistSourceRef` | Multi-source entries |
| `AppPlaylistStore` | App-owned JSON playlists |
| `PlexClient` | PMS sections + prefer-original stream URLs |
| `RadioCatalog` | Curated + user stream URLs |
| `MetadataLoader` / `PersistenceManager` / lyrics / artwork | Upstream |

## Changelog vs upstream

See [CHANGELOG.md](CHANGELOG.md).

## License

[MPL-2.0](LICENSE) — same as upstream LocalMusic.
