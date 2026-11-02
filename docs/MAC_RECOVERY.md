# ChibiAudio for Mac: recovery record (2026-11-01 contract)

Branch `forge/mac-recovery`, cut from `origin/Dev_Erick` (9a0a8ef, which already holds the Up Next queue and macOS target commits). This file records what changed, what was verified and how, and what is still open. Build success and passing tests do not by themselves establish visual or behavioral parity. Every item below says how it was checked.

## Root cause of the clipped sheets

macOS sizes a sheet window from its content's ideal size. A `NavigationStack` around a `List`, `Form` or `ScrollView` reports almost no ideal height, so Settings and Up Next attached as a 470 x 113 window that held only the title bar and Done button. iOS presents sheets at system detents, which is why only the Mac broke.

**Fix:** every sheet in the app (23 callers) now goes through `chibiSheet(isPresented:/item:size:)` in `LocalMusic/Theme/PlatformChrome.swift`. On the Mac it gives the content a minimum and ideal frame (compact, regular or large). On iOS it is a no-op, so iOS presentation is unchanged.

**Evidence:** `ChibiAudioMacTests/MacSheetPresentationTests.swift` presents the real views in an AppKit window and measures the attached sheet window:

| Sheet caller | Window | Sheet window |
|---|---|---|
| Up Next through a plain `.sheet` (the old code path) | 960 x 600 | **470 x 113** (reproduces the bug) |
| Up Next through `chibiSheet` (queue of 5 / empty) | 960 x 600 | 520 x 560 / 520 x 560 |
| Up Next through `chibiSheet` | 1440 x 900 | 520 x 585 |
| Settings (iOS-style sheet content) | 960 x 600 / 1440 x 900 | 520 x 560 / 520 x 585 |
| Lyrics (no lyrics / unsynced lyrics) | 960 x 600 | 560 x 560 |
| Add to Playlist (from Now Playing, Songs, Plex, Bandcamp, Radio) | 960 x 600 | 470 x 505 |
| Add Tracks (playlist detail) | 960 x 600 | 520 x 560 |
| Make a Playlist (smart playlist) | 960 x 600 | 560 x 560 |
| Plex sign-in (signed out) | 960 x 600 | 470 x 505 |
| Paywall | 960 x 600 | 560 x 560 |
| What's New (launch and archive) | 960 x 600 | 560 x 560 |
| Settings window content (`MacSettingsView`) | n/a | 640 x 560 fitting |

The seed picker inside Make a Playlist and the folder pickers (iOS only) use the same helper but are not measured separately. A launch of the isolated build (below) attached the first-run What's New sheet at 560 x 560 in a 960 x 652 window, measured with CGWindowList.

## What changed on the Mac

- **Settings window.** ChibiAudio > Settings... (Command-comma) opens a native Settings scene with General, Sources, Playback, Plus and Diagnostics tabs. Each tab is the shared `SettingsView` filtered to one `SettingsPane`, so no settings logic is duplicated. The gear on Home and Songs opens the same window. Nested navigation (Logs) works inside the window, and sheets from it (Plex sign-in, Paywall, What's New) use `chibiSheet`. CarPlay and Watch stubs are hidden on the Mac. iOS keeps its single Settings list, with the same sections in the same order.
- **Discoverable sources.** The sidebar has Listen (Home, Now Playing), Library (Songs, Albums, Artists, Playlists) and Sources (Radio, Plex, Bandcamp). The music folder is pinned under the sidebar, and File > Choose Music Folder... (Command-O) plus Reload Music (Command-R) are in the menu. The Plex and Bandcamp links in Settings jump to the sidebar. Bandcamp's unconfigured state opens Settings on the Sources tab. Home's Plex tile opens the Plex source.
- **Albums and Artists** are built from real track tags (`LibraryBrowseIndex`). Albums group by title plus folder; disc subfolders count as their parent. Untagged files keep the loader's "Unknown Album" and "Unknown Artist" labels. No artwork or metadata is invented.
- **Persistent transport.** A player bar under every section except Now Playing shows artwork, title, artist, source chip, previous/play/next, shuffle, repeat, a scrubber (LIVE for streams), the AirPlay picker and an Up Next toggle. Changing sidebar sections does not touch the player.
- **Browsable queue.** Up Next opens in an inspector column beside any section (player bar, Now Playing toolbar, or Playback > Show Up Next, Option-Command-U). It shares `UpNextList` with the iOS sheet: drag to reorder, Delete or the context menu to remove, Play Now, and a cancelable Clear. Every change still goes through `AudioPlayerManager`, so queue persistence is unchanged.
- **Keyboard.** The Playback menu has Play/Pause (Space), Next and Previous (Command-Right and Command-Left), Shuffle, Repeat, Show Up Next and Go to Now Playing (Command-0). The View menu has Command-1 to Command-8 for the sidebar sections. `MacPlaybackKeyMonitor` gives Space and Command-arrows to the focused field editor while text is being edited, so typing in Search, Settings or a playlist name never toggles playback or skips tracks.
- **Accessibility.** Transport buttons in the player bar, Now Playing and the mini player now carry labels: Previous Track, Play/Pause, Next Track, Shuffle and Repeat (with values), Audio Output, Up Next and Settings. The Now Playing and mini player labels also apply on iOS.
- **Fix found while tracing callers:** Home's Choose Folder actions on the Mac set a sheet flag that had no sheet attached, so they did nothing. They now open the folder panel.

## Mac audio: what is supported and what is not

| Capability | iOS | Mac after this change | Status |
|---|---|---|---|
| Output device | AVAudioSession route; DAC route indicator | Plays through the system default output and follows device changes. Settings > Playback shows the real device name, nominal sample rate and connection type, read from CoreAudio | Read only. The app never changes the device or its rate |
| AirPlay | `AVRoutePickerView` in Now Playing | `AVRoutePickerView` (AppKit) in the player bar and Now Playing, bound to the app's `AVPlayer` | Built. **Not verified with an AirPlay device** |
| Hi-res / DAC mode, bit-perfect pill | Yes (preferred sample rate, EQ forced off) | Not available. The Mac never shows a bit-perfect claim | **Engine gap:** needs a CoreAudio output path (device nominal-rate switching and hog mode) |
| Sample-rate chip in Now Playing | Route sample rate | Not shown. The device rate is in Settings > Playback | By design |
| Equalizer | `EqualizerView` UI | Not shown ("Not available on Mac") | **Existing gap on both platforms:** `EqualizerController.audioUnit()` builds an `AVAudioUnitEQ` that is never attached to the `AVPlayer` playback path, so on iOS the EQ settings currently do not change the sound either. A working EQ needs `AVAudioEngine` playback or an `MTAudioProcessingTap` |
| DSD (DoP) | Refused (encoder not shipped) | Refused | Unchanged |
| OGG/Opus/WavPack | Refused (needs a decoder) | Refused | Unchanged |
| Media keys / Now Playing center | MPRemoteCommandCenter | Same shared code | Unchanged; not re-verified here |
| AutoMix, spatial audio, lossless catalog, Apple Music catalog playback | Not present | Not present | Not claimed. They appeared only in the reference app |

## Verification run for this branch

| Check | Result |
|---|---|
| `xcodebuild build`, scheme ChibiAudio (macOS arm64) | Succeeded |
| `xcodebuild build`, scheme LocalMusic (iOS Simulator) | Succeeded |
| iOS unit tests (`LocalMusicTests`, iPhone simulator, iOS 27.1) | 261 passed (246 before this branch plus 15 new: key routing, album/artist grouping, Settings panes, sheet sizes, tab raw values) |
| Mac-hosted tests (`ChibiAudioMacTests`) | 15 passed: sheet sizes for every caller, the root-cause reproduction, Settings window size and pane rendering, Space and Command-Left delivered to a focused text field rather than the menu, and Settings... (Command-comma) plus the Playback bindings present in the real menu bar |
| Launch smoke test of the isolated build | Launched without a crash. Main window 960 x 652, first-run sheet 560 x 560 |
| Independent code review of the diff | 7 findings, all fixed in `8253ecf`. It confirmed that iOS Settings has the same sections and order |

Run the Mac tests with the sandbox stripped and a throwaway bundle ID. A sandboxed ad-hoc test host cannot accept the test bundle, and the throwaway ID keeps the test host's defaults separate from the installed app's:

```
xcodegen generate
xcodebuild test -project LocalMusic.xcodeproj -scheme ChibiAudio \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  CODE_SIGN_ENTITLEMENTS= PRODUCT_BUNDLE_IDENTIFIER=com.chibitek.forgeverify.chibiaudio
```

## Open: checks that need a person at the Mac

Screen Recording and Accessibility are not granted to the automation shell, so no screenshots or clicks were possible. Engineering should check the following against an isolated build, using real, already-authorized content. Do not run these checks against the installed app or connect new accounts.

1. Settings: open it from the menu, Command-comma and the gear on Home and Songs. Every tab renders and scrolls at the minimum window size and when enlarged. Logs pushes and pops. Plex sign-in, Paywall and What's New sheets open and close.
2. Up Next: the inspector shows the actual current and upcoming tracks. Play Next and Add to Queue, drag reorder, remove, and Clear followed by Cancel all work. The queue survives a relaunch, and tracks advance at the end of a song.
3. Every sheet caller, checked visually in its non-empty, empty and error states.
4. Sources: Plex browse and play with the existing sign-in. Bandcamp browse and play with the existing Subsonic credentials. Radio browse, search and custom stream. Record any account or service dependency that blocks a check.
5. Library: search filtering, sorting, Albums and Artists against real tags, the playlist lifecycle (create, add, rename, delete) in a scratch playlist, lyrics, visualizers, and playback navigation.
6. Keyboard and VoiceOver: Space in Search and Settings types a space. Space elsewhere plays or pauses. Command-arrows outside text fields skip tracks. VoiceOver reads every transport control's label. Switching sections does not reset transport.
7. Audio: audible output, seeking, the AirPlay picker with a real device, and the device name and rate in Settings after changing them in Audio MIDI Setup.
8. iOS regression on a device or simulator: Settings (every section, DAC/EQ, Plex, Bandcamp, crash reporting), the Up Next sheet, and sources.
