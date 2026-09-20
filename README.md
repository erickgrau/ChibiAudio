# ChibiAudio

**Offline HiFi Player** — free + optional Plus personal iOS music player. Fork of [j23n/localmusic](https://github.com/j23n/localmusic) (MPL-2.0), not a greenfield app.

| | |
|---|---|
| **Display name** | ChibiAudio |
| **App Store subtitle** | Offline HiFi Player |
| **Bundle ID** | `com.chibitek.ChibiAudio` |

LocalMusic architecture stays under `LocalMusic/` (folder picker, security-scoped bookmarks, library scan, AVPlayer queue, lyrics, lock screen / Now Playing). ChibiAudio layers branding, free-tier sources, and optional **ChibiAudio Plus** ($1.99/mo).

See [NOTICE](NOTICE) for upstream attribution.

## What you get

| Capability | Free | Plus ($1.99/mo) |
|---|---|---|
| Offline On My iPhone / app Documents via Files + security-scoped bookmarks | Yes | Yes |
| iCloud Drive / Google Drive folders via system Files picker + bookmarks | Yes | Yes |
| Lossless / hi-res PCM (FLAC, ALAC, WAV, AIFF, high-bitrate AAC/M4A, MP3) | Yes | Yes |
| DSD (`.dsf`/`.dff`) — DoP preferred; never silent lossy fall-back | Policy yes | Same |
| THX Onyx bit-perfect PCM (USB route, Hi-res/DAC mode, EQ bypass) | Yes | Yes |
| Cross-source app-owned playlists (local/cloud + Plex + radio + Bandcamp) | Yes | Yes |
| Plex personal library — prefer direct/original stream | Yes | Yes |
| Bandcamp purchased collection (Subsonic API) | Yes | Yes |
| Free internet radio (Radio Browser + Icecast/Shoutcast URL) | Yes | Yes |
| Core visuals (album art · track art) | Yes | Yes |
| Banner ads (never over Now Playing / DAC / visualizer) | Yes* | No ads |
| All visualizer modes (VU, LED, spectrum, kaleidoscope, vectors, vinyl, mixtape) | — | Yes |
| CarPlay stubs (Apple Audio templates: large NP art, browse, queue) | — | Yes |
| Apple Watch companion stubs | — | Yes |

\* Ads are a no-op when `ADMOB_APP_ID` / `GADApplicationIdentifier` is empty (CI / default builds).

StoreKit product: `com.chibitek.ChibiAudio.plus.monthly` (auto-renewable). Restore Purchases is in Settings and on the paywall.

Out of free v1: Spotify / YouTube Music–style catalogs; licensed MQA Core decode; inventing Dist certs or CarPlay entitlements.

## Sources matrix

| Source | Free? | Notes |
|---|---|---|
| On My iPhone / Documents | Yes | Files folder picker + bookmarks; plays fully offline |
| iCloud Drive | Yes | Same picker; download-to-play when ubiquitous |
| Google Drive (Files provider) | Yes | Install Drive app → enable in Files → pick folder |
| App-owned mixed playlists | Yes | No sub to mix offline + Plex + radio + Bandcamp in *our* DB |
| Free radio (Radio Browser + Icecast / Shoutcast URL) | Yes | Radio tab |
| Plex Media Server (your library) | Yes* | Token + LAN stream; *some remote/Plexamp features may need Plex Pass |
| Bandcamp (purchased collection) | Yes | Settings → Bandcamp; server `https://bandcamp.com/api/subsonic`; Fan Settings Subsonic user/pass |
| Apple Music catalog | Sub required to *play* | Optional later; gated on `canPlayCatalogContent` |
| Spotify / YT Music catalogs | No | Out of free v1 |

### Research lock

- App-owned mixed playlists = free.
- Apple Music catalog play needs the user’s Apple Music subscription.
- Plex: basic stream of *your* PMS library on LAN does not require Plex Pass; remote/Pass caveats apply.
- Bandcamp: official Subsonic API only — purchased collection; no HTML scrape.
- Plus is optional. Free core stays usable without it.

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
- Bundle ID: `com.chibitek.ChibiAudio` · Display name: **ChibiAudio** · App Store subtitle: **Offline HiFi Player**
- Xcode target/module name remains `LocalMusic` (upstream layout)
- Optional StoreKit testing: scheme uses `LocalMusic/Configuration/ChibiAudio.storekit`
- Ads: leave `GADApplicationIdentifier` unset for CI; set `ADMOB_APP_ID` / plist value for release builds that link Google Mobile Ads

### Plex token

1. Obtain `X-Plex-Token` from your Plex account / server.
2. Settings → Plex → `http://…:32400` + token → Browse Plex Music.
3. Prefer LAN (`NSAllowsLocalNetworking` enabled).

### Bandcamp Subsonic

1. Bandcamp → Fan Settings → Subsonic → generate username / password.
2. Settings → Bandcamp → server defaults to `https://bandcamp.com/api/subsonic` → save → Browse Bandcamp Collection.
3. Streams purchased collection only.

### Google Drive / iCloud

1. Enable the provider under Files → Browse.
2. ChibiAudio → choose folder via document picker.
3. Re-scan after adding files; cloud placeholders download-to-play when possible.

## Architecture (still localmusic)

| Module | Role |
|---|---|
| `LocalMusicApp` | Tabs: Home, Library, Now Playing, Playlists, Radio |
| `AudioPlayerManager` | AVPlayer queue, remote commands, DAC session, cloud prep |
| `CodecRouter` / `DACSession` / `DSDRouter` | Format matrix + THX Onyx USB path |
| `EqualizerController` | 10-band EQ + presets; forced off in DAC bit-perfect mode |
| `Playlist` + `PlaylistSourceRef` | Multi-source entries |
| `AppPlaylistStore` | App-owned JSON playlists |
| `PlexClient` | PMS sections + prefer-original stream URLs |
| `BandcampSubsonicClient` | Bandcamp Subsonic purchased collection |
| `PlusStore` / `PaywallView` | StoreKit Plus + Onyx×Glass paywall |
| `AdBannerView` | Free-tier banner; no-op when AdMob ID empty |
| `RadioCatalog` / `RadioBrowserClient` | Curated + Radio Browser directory |
| `MetadataLoader` / `PersistenceManager` / lyrics / artwork | Upstream |

## Changelog vs upstream

See [CHANGELOG.md](CHANGELOG.md).

## License

[MPL-2.0](LICENSE) — same as upstream LocalMusic.
