# CHANGELOG (ChibiAudio fork)

## Free v1 — Soft PASS (vs j23n/localmusic)

Locked bar only — no visual redesign in this release.

### Branding
- Display name **ChibiAudio**, bundle `com.chibitek.ChibiAudio`
- Target/module remains `LocalMusic`
- `NOTICE` credits j23n/localmusic (MPL-2.0)
- No IAP

### Offline + cloud folders
- Upstream Files picker + security-scoped bookmarks retained
- `CloudFileAccess` download-to-play for iCloud / Files providers
- README: iCloud + Google Drive via Files setup

### Formats + THX Onyx
- `CodecRouter` native lossless/lossy matrix; OGG/Opus/WV needs-decode; DSD flagged
- `DACSession` Hi-res/DAC mode, USB → THX Onyx labeling, preferred rate from track
- MQA = Onyx renderer passthrough only (no licensed Core decoder)
- DSD = DoP intent; refuse silent lossy fall-back

### Playlists
- Multi-source `PlaylistSourceRef` (local, stream, Plex, gated Apple Music)
- App-owned JSON playlists; m3u keeps http URLs

### Free sources
- Radio tab: Radio Browser directory (country / genre / search) + favorites + paste URL
- Plex token browse/stream (prefer original/direct)

### EQ + upstream player strengths
- 10-band EQ + presets; bypassed when DAC/bit-perfect
- Lyrics, background audio, lock screen unchanged from upstream

## Wave 1 Soft PASS (player surfaces)

- **Artwork:** embedded metadata → `folder.jpg` / `cover.*` sidecar → placeholder; big Now Playing hero art
- **Lyrics:** Soft Glass sheet with synced auto-scroll, unsynced text, `.lrc` sidecar + embedded; empty state
- **AirPlay:** `AVRoutePickerView` on Now Playing; `allowsExternalPlayback` kept on; USB DAC bit-perfect path unchanged
- **Add to Playlist:** shared sheet from Now Playing / Library / Radio / Plex (pick existing or create)
- **Polish:** Onyx×Glass placeholders, lyrics chrome, playlist mosaic empties

## Soft PASS Home

- **Home** first tab (default landing): Continue card, Recent, Playlists shortcuts, Library shortcuts
- `RecentsStore` (Documents/`recents.json`) records plays for Recent / Continue fallback
- Empty Soft PASS when no library yet → Add Folder
- Settings remains gear sheet (not a tab); mini player chrome unchanged
- No CarPlay / Watch / Apple Music catalog

## Wave 2 Soft PASS (radio directory)

- **Radio Browser:** community mirrors, `User-Agent: ChibiAudio/1.0`, light list cache, click report on play
- **Radio tab:** Browse (country + genre/tag), Search by name, Favorites (custom URL kept)
- **Station rows:** name, country, tags/genre, bitrate; tap to play; Add to Playlist
- **Empty / offline** states on Soft Glass × Onyx canvas
- HTTP media streams allowed via `NSAllowsArbitraryLoadsInMedia` (API stays HTTPS)
