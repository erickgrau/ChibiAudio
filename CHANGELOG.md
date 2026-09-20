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
- Radio tab (curated + paste URL)
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
