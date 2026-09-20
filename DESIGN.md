# DESIGN — Soft PASS (Onyx Dark + Soft Glass)

Visual Soft PASS for ChibiAudio free v1. **Blend A (Onyx Dark) + B (Soft Glass materials).**  
Feature matrix and playback logic are unchanged except display hooks (source chips, route/rate chrome, EQ dimming).

## Direction

| Token | Value | Role |
|---|---|---|
| Canvas | `#0A0A0C` → `#121214` | Near-black, not crushed OLED |
| Soft Glass | `.ultraThinMaterial` / `.thinMaterial` | Tab bar, Now Playing chrome, lyrics, settings, mini player |
| Amber | `#F5A623` | Hi-res / PCM “LED”, accent tint, transport highlights |
| Teal | `#2EC4B6` | USB / DAC connected, bit-perfect pill |
| Type | SF Mono (`.monospaced`) | Sample-rate chip next to transport |

Dark is the default (`preferredColorScheme(.dark)`). Light mode is optional later — not in this PR.

## IA

Tabs: **Home · Library · Now Playing · Playlists · Radio**  
Settings stays under **gear** (Home / Library) — not a tab.  
Plex stays under **Settings → Browse Plex Music**.

## Key surfaces

### Home (default landing)
- Soft glass **Continue** card (big art + title/artist) → opens Now Playing or resumes last play
- **Recent** horizontal strip from `RecentsStore` (Documents/`recents.json`)
- **Playlists** shortcut chips → playlist detail or Playlists tab
- **Library** shortcuts: Folders / All tracks / Radio
- Empty Soft PASS when no library yet (point to Add Folder)
- Mini player chrome matches Wave 1

### Now Playing
- Huge hero (~52% viewport height), minimal chrome
- Soft PASS **visualizer suite** on the hero (swipe or glass picker); transport unchanged
  - Album art (default) · Track art · VU · 1980s LED · EQ spectrum · Kaleidoscope · Vectors · Vinyl · Mixtape
  - Spectrum modes meter a **parallel muted AVPlayer** tap — never EQ / mix on the DAC bit-perfect path
  - Vinyl + mixtape animate while playing; last mode persisted
- Soft glass transport card under art
- `SourceChip` + monospace `SampleRateChip` (PCM · kHz)
- Pill **“Bit-perfect → THX Onyx”** when DAC mode **and** USB audio route
- Lyrics Soft PASS sheet (`.ultraThinMaterial` / soft glass): synced auto-scroll, unsynced text, or empty state
- AirPlay Soft PASS: `AVRoutePickerView` on transport row
- Add to Playlist Soft PASS sheet from Now Playing

### Library / Playlists / Radio
- Onyx canvas, glass navigation bar
- Radio: Browse (country / genre), Search, Favorites — Radio Browser directory + custom URL
- Source chips on rows / onboarding (On Device · iCloud · Drive · Plex · Radio)
- Amber accent for current track / CTAs

### Settings + EQ
- Glass nav; Audio section shows teal DAC indicator + bit-perfect pill
- EQ behind gear → Equalizer; when DAC bit-perfect path is active, controls are **disabled/dimmed** with an explicit reason (teal icon)

### Mini player
- Soft glass capsule, amber progress, optional source chip

## Code map

| File | Role |
|---|---|
| `LocalMusic/Theme/ChibiTheme.swift` | Colors, materials, typography, `MediaSourceKind`, canvas helpers |
| `LocalMusic/Components/ChibiChrome.swift` | `SourceChip`, `SampleRateChip`, `BitPerfectOnyxPill`, `DACRouteIndicator` |
| `LocalMusic/Views/HomeView.swift` | Soft PASS Home tab |
| `LocalMusic/Services/RecentsStore.swift` | Minimal play-history for Home Recent |
| `LocalMusic/Theme/TabRouter.swift` | Shared tab selection for Home shortcuts |
| `LocalMusic/Services/RadioBrowserClient.swift` | Radio Browser mirrors, UA, cache |
| `LocalMusic/Views/RadioView.swift` | Browse / Search / Favorites Soft PASS |
| `LocalMusic/Models/VisualizerMode.swift` | Soft PASS Now Playing visualizer modes + persistence |
| `LocalMusic/Services/Visualizer/*` | Parallel-bus FFT metering (DAC path untouched) |
| `LocalMusic/Components/Visualizers/*` | Hero visualizer suite UI |
| Views listed above | Applied chrome only — no free-v1 feature changes |

## Screenshots

iOS Simulator is not available in this Linux cloud agent environment. Capture locally after `xcodegen && open LocalMusic.xcodeproj`:

1. Home (default) — empty library Soft PASS + Add Folder  
2. Home — Continue card + Recent strip + playlist chips (Onyx×Glass)  
3. Library onboarding with source chips on Onyx canvas  
4. Now Playing visualizer Soft PASS (swipe modes; vinyl/mixtape while playing)  
5. Now Playing rate chip + bit-perfect pill (USB DAC connected)  
6. Radio Soft PASS — Browse / Search / Favorites (Radio Browser)  
7. Settings Audio · THX Onyx with EQ link  
8. Equalizer dimmed under DAC mode  

## Out of scope

- Light mode default, IAP, MQA Core UI, Spotify, visual redesign beyond this Soft PASS lock
