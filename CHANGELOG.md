# CHANGELOG (ChibiAudio fork)

## ChibiAudio Plus + Bandcamp + ads

- **Plus** StoreKit auto-renewable `com.chibitek.ChibiAudio.plus.monthly` ($1.99/mo): no ads, all visualizer modes, CarPlay / Watch stubs
- **Paywall** Onyx × Soft Glass sheet with Restore Purchases (Settings + visualizer lock)
- **Ads** free-tier banner on Home / Library / Playlists / Radio only — never Now Playing, DAC, or visualizer; no-op when `ADMOB_APP_ID` / `GADApplicationIdentifier` empty
- **Bandcamp Subsonic** Settings credentials → `https://bandcamp.com/api/subsonic` purchased collection (no HTML scrape)
- **Visualizer gate** album/track art free; VU / LED / spectrum / kaleidoscope / vectors / vinyl / mixtape require Plus
- **CarPlay / Watch** stubs only — Apple Audio templates (large NP art, browse, queue); phone keeps visualizer suite; no Dist certs or CarPlay entitlement invented

## Free v1 baseline (vs j23n/localmusic)

Locked free bar — Plus is optional on top.

### Branding
- Display name **ChibiAudio**, bundle `com.chibitek.ChibiAudio`
- Target/module remains `LocalMusic`
- `NOTICE` credits j23n/localmusic (MPL-2.0)

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
- Bandcamp Subsonic purchased collection

### EQ + upstream player strengths
- 10-band EQ + presets; bypassed when DAC/bit-perfect
- Lyrics, background audio, lock screen unchanged from upstream

## Wave 1 player surfaces

- **Artwork:** embedded metadata → `folder.jpg` / `cover.*` sidecar → placeholder; big Now Playing hero art
- **Lyrics:** Soft Glass sheet with synced auto-scroll, unsynced text, `.lrc` sidecar + embedded; empty state
- **AirPlay:** `AVRoutePickerView` on Now Playing; `allowsExternalPlayback` kept on; USB DAC bit-perfect path unchanged
- **Add to Playlist:** shared sheet from Now Playing / Library / Radio / Plex (pick existing or create)
- **Polish:** Onyx×Glass placeholders, lyrics chrome, playlist mosaic empties

## Home

- **Home** first tab (default landing): Continue card, Recent, Playlists shortcuts, Library shortcuts
- `RecentsStore` (Documents/`recents.json`) records plays for Recent / Continue fallback
- Empty state when no library yet → Add Folder
- Settings remains gear sheet (not a tab); mini player chrome unchanged

## Wave 2 radio directory

- **Radio Browser:** community mirrors, `User-Agent: ChibiAudio/1.0`, light list cache, click report on play
- **Radio tab:** Browse (country + genre/tag), Search by name, Favorites (custom URL kept)
- **Station rows:** name, country, tags/genre, bitrate; tap to play; Add to Playlist
- **Empty / offline** states on Soft Glass × Onyx canvas
- HTTP media streams allowed via `NSAllowsArbitraryLoadsInMedia` (API stays HTTPS)

## Now Playing visualizer suite

- Swipeable / picker hero modes (transport unchanged): Album art · Track art · VU meters · 1980s LED bar · EQ spectrum · Kaleidoscope · Vectors · Vinyl · Cassette/mixtape
- Spectrum modes: FFT/levels from a **parallel muted** analysis `AVPlayer` tap — main DAC playback path stays bit-perfect (no EQ insert)
- Vinyl disc + mixtape reels animate while playing; label/spine use album art / track·artist
- Last visualizer mode persisted (`nowPlayingVisualizerMode`); Plus-only modes clamp to album art when unsubscribed
