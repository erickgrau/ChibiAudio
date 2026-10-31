# LocalMusic

iOS and macOS music player that plays audio files from a user-selected folder. SwiftUI, no external dependencies. Two XcodeGen targets (`LocalMusic` iOS, `ChibiAudio` macOS) share the `LocalMusic/` sources — never copy files between them.

## Build

Project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`. **`LocalMusic.xcodeproj` is gitignored** — always run XcodeGen after checkout so sources such as `LocalMusic/Theme/TabRouter.swift` land in the pbxproj:

```
xcodegen generate   # regenerate LocalMusic.xcodeproj (required after clone/pull)
xcodebuild -project LocalMusic.xcodeproj -scheme LocalMusic -destination 'generic/platform=iOS' build
xcodebuild -project LocalMusic.xcodeproj -scheme ChibiAudio -destination 'platform=macOS,arch=arm64' build
```

Requires Xcode 16+, targets iOS 18+ / macOS 15+, Swift 6 with `SWIFT_STRICT_CONCURRENCY: complete`. Unit tests live in `LocalMusicTests/` (iOS-hosted) and run via `xcodebuild test`; CI runs them on every PR. Cross-app conventions are documented in `.claude/CONVENTIONS.md`.

## Architecture

Shared SwiftUI app with tabs on iOS (Home default, Library, Now Playing, Playlists, Radio) and a NavigationSplitView sidebar on macOS. State lives in `@Observable` stores injected via `@Environment(_:)`.

```
LocalMusic/
  LocalMusicApp.swift         # @main; iOS TabView / MacRootView wiring, playback
                              # menu (mac: space, Cmd+Left/Right), scene-phase rescan
  Logging.swift               # Log.<category> wrapping os.Logger
  Models/                     # Track, Playlist, PlaylistSeed, RepeatMode, SyncedLyricLine, VisualizerMode
  Services/                   # AudioPlayerManager, LibraryStore, PlaybackQueue,
                              # MetadataLoader, PersistenceManager, RecentsStore,
                              # ArtworkCache, LyricsCache, Visualizer/, SmartPlaylist/
  Views/                      # HomeView, LibraryView, NowPlayingView, PlaylistsView,
                              # SmartPlaylistView, PlaylistDetailView, MiniPlayerView,
                              # MacRootView, SettingsView, RadioView
  Components/                 # ArtworkView, DocumentPicker, Visualizers/
  Theme/PlatformChrome.swift   # PlatformImage/PlatformColor, iOS-only nav chrome shims
  Configuration/              # ChibiAudioMac.entitlements (App Sandbox, user-selected read-only)
```

- `LocalMusicApp.swift` — Entry point; `rootContent` picks the iOS TabView or `MacRootView` sidebar, `@State` stores, `scenePhase`-driven `LibraryStore.checkForExternalChanges()`
- `Views/MacRootView.swift` — macOS `NavigationSplitView`: sidebar over the same `ChibiTab` sections, mini player under every section except Now Playing
- `Services/AudioPlayerManager.swift` — `@Observable @MainActor`; wraps `AVPlayer`, owns lock-screen/Control Center integration (shared `MPRemoteCommandCenter` code serves both platforms' media keys)
- `Services/LibraryStore.swift` — `@Observable @MainActor`; slim `Track` array, debounced filter/sort pipeline, playlist CRUD
- `Services/RecentsStore.swift` — Minimal play history for Home Recent / Continue
- `Services/SmartPlaylist/` — Multi-seed playlist scoring + MusicBrainz/ListenBrainz enrichment
- `Services/Visualizer/` — Soft PASS parallel-bus FFT metering (never on DAC path)
- `Services/MetadataLoader.swift` — Recursive folder scan, ID3/iTunes metadata extraction, playlist (m3u/pls) parsing and writing
- `Services/PersistenceManager.swift` — `@unchecked Sendable`; security-scoped folder bookmarks (`.withSecurityScope` on macOS, plain on iOS), JSON library cache, folder mtime
- `Models/Track.swift`, `Playlist.swift`, `PlaylistSeed.swift`, `RepeatMode.swift`, `SyncedLyricLine.swift`, `VisualizerMode.swift` — slim value types

### Views

- `Views/HomeView.swift` — Soft PASS Home: Continue, Recent, Playlists, Library shortcuts
- `Views/LibraryView.swift` — Track list with search; `TrackRow` and `NowPlayingBars` components live here
- `Views/NowPlayingView.swift` — Full-screen player with Soft PASS visualizer hero, ambient color, synced lyrics, seek bar
- `Views/PlaylistsView.swift` — Playlist list with creation/deletion; `PlaylistMosaicView` thumbnail component
- `Views/SmartPlaylistView.swift` — Make a Playlist Soft PASS (seeds → generate → preview → save)
- `Views/PlaylistDetailView.swift` — Playlist tracks with inline missing-file warnings; `AddTracksSheet`, `MissingTrackRow`
- `Views/MiniPlayerView.swift` — Compact bottom-bar player overlay
- `Views/UpNextView.swift` — Queue sheet from Now Playing: current track pinned, Up Next reorder/remove/clear
- `Views/SettingsView.swift` — Folder selection, rescan, stats; on the Mac the DAC/EQ section is informational (system default output, no forced sample rate)
- `Components/DocumentPicker.swift` — `UIViewControllerRepresentable` wrapper on iOS; `NSOpenPanel.pickFolder` on macOS
- `Components/ArtworkView.swift` — async-loading artwork with placeholder
- `Components/QueueActions.swift` — shared Play Next / Add to Queue context-menu items and leading swipe actions
- `Components/Visualizers/` — Soft PASS Now Playing hero visualizer suite

## Key patterns

- Platform gating: shared files use `#if os(iOS)` for UIKit/AVAudioSession/DACSession code; UI-only API differences go through `Theme/PlatformChrome.swift` shims (`PlatformImage`, `PlatformToolbar`, `chibiNavChrome`, etc.). AdMob (`Services/Ads/`) is excluded from the mac target sources entirely
- Folder access uses security-scoped bookmarks (`PersistenceManager`); `AudioPlayerManager.startAccessingFolder()` must be active for file reads
- Playlists store `trackURLs: [URL]` and parallel `rawPaths: [String]` — always keep both in sync when mutating
- Library tracks are matched to playlist entries by comparing `.standardized` URLs
- `PlaybackQueue` is history + current + Up Next in one array split at `currentIndex`; every mutation goes through `AudioPlayerManager.syncPublishedFromQueue()`, which also persists it to `Documents/queue.json`
- Playlist files are rewritten atomically on every mutation via `MetadataLoader.writePlaylist()`
