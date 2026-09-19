# CHANGELOG (ChibiAudio fork)

## Unreleased — fork modifications vs j23n/localmusic

### Branding
- Display name **ChibiAudio**, bundle `com.chibitek.ChibiAudio`
- Target/module name remains `LocalMusic` (upstream layout)
- `NOTICE` credits j23n/localmusic (MPL-2.0)

### Audio / THX Onyx
- `DACSession` + Hi-res/DAC mode; USB route labeled for THX Onyx (ES9281PRO)
- Preferred sample rate from track / up to 192 kHz — no forced 48 kHz crush
- MQA: passthrough to Onyx renderer only (no software MQA decode)
- DSD: DoP intent; refuse silent lossy fall-back (DoP encoder not in free v1 yet)
- EQ forced off when DAC/bit-perfect path is active

### Library / playlists
- `CodecRouter` native vs needs-decode vs DSD
- `CloudFileAccess` for iCloud / Files-provider materialization
- Multi-source `PlaylistSourceRef` + app-owned JSON playlists
- m3u import/export keeps http stream URLs

### Free sources
- Radio tab (curated + paste Icecast/Shoutcast URL)
- Plex Media Server token + browse/stream (LAN ATS local networking)

### Docs
- README sources matrix, research lock, Hardware (THX Onyx), build steps
