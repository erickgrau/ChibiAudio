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

Tabs: **Library · Now Playing · Playlists · Radio**  
Plex stays under **Settings → Browse Plex Music** (not a fifth tab).

## Key surfaces

### Now Playing
- Huge album art (~52% viewport height), minimal chrome
- Soft glass transport card under art
- `SourceChip` + monospace `SampleRateChip` (PCM · kHz)
- Pill **“Bit-perfect → THX Onyx”** when DAC mode **and** USB audio route
- Lyrics Soft PASS sheet (`.ultraThinMaterial` / soft glass): synced auto-scroll, unsynced text, or empty state
- AirPlay Soft PASS: `AVRoutePickerView` on transport row
- Add to Playlist Soft PASS sheet from Now Playing

### Library / Playlists / Radio
- Onyx canvas, glass navigation bar
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
| Views listed above | Applied chrome only — no free-v1 feature changes |

## Screenshots

iOS Simulator is not available in this Linux cloud agent environment. Capture locally after `xcodegen && open LocalMusic.xcodeproj`:

1. Library onboarding with source chips on Onyx canvas  
2. Now Playing with huge art + rate chip + bit-perfect pill (USB DAC connected)  
3. Settings Audio · THX Onyx with EQ link  
4. Equalizer dimmed under DAC mode  

## Out of scope

- Light mode default, IAP, MQA Core UI, Spotify, visual redesign beyond this Soft PASS lock
