# LocalMusic

iOS music player that plays audio files from a user-selected folder. SwiftUI, no external dependencies.

## Build

Project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`. **`LocalMusic.xcodeproj` is gitignored** — always run XcodeGen after checkout so sources such as `LocalMusic/Theme/TabRouter.swift` land in the pbxproj:

```
xcodegen generate   # regenerate LocalMusic.xcodeproj (required after clone/pull)
xcodebuild -project LocalMusic.xcodeproj -scheme LocalMusic -destination 'generic/platform=iOS' build
```

Requires Xcode 16+, targets iOS 18+, Swift 6 with `SWIFT_STRICT_CONCURRENCY: complete`. Unit tests live in `LocalMusicTests/` and run via `xcodebuild test`; CI runs them on every PR. Cross-app conventions are documented in `.claude/CONVENTIONS.md`.

## Architecture

Single-target SwiftUI app with tabs: Home (default), Library, Now Playing, Playlists, Radio. State lives in `@Observable` stores injected via `@Environment(_:)`.

```
LocalMusic/
  LocalMusicApp.swift         # @main; tab wiring, scene-phase rescan
  Logging.swift               # Log.<category> wrapping os.Logger
  Models/                     # Track, Playlist, PlaylistSeed, RepeatMode, SyncedLyricLine, VisualizerMode
  Services/                   # AudioPlayerManager, LibraryStore, PlaybackQueue,
                              # MetadataLoader, PersistenceManager, RecentsStore,
                              # ArtworkCache, LyricsCache, Visualizer/, SmartPlaylist/
  Views/                      # HomeView, LibraryView, NowPlayingView, PlaylistsView,
                              # SmartPlaylistView, PlaylistDetailView, MiniPlayerView,
                              # SettingsView, RadioView
  Components/                 # ArtworkView, DocumentPicker, Visualizers/
```

- `LocalMusicApp.swift` — Entry point; tab navigation (Home default), `@State` stores, `scenePhase`-driven `LibraryStore.checkForExternalChanges()`
- `Services/AudioPlayerManager.swift` — `@Observable @MainActor`; wraps `AVPlayer`, owns lock-screen/Control Center integration
- `Services/LibraryStore.swift` — `@Observable @MainActor`; slim `Track` array, debounced filter/sort pipeline, playlist CRUD
- `Services/RecentsStore.swift` — Minimal play history for Home Recent / Continue
- `Services/SmartPlaylist/` — Multi-seed playlist scoring + MusicBrainz/ListenBrainz enrichment
- `Services/Visualizer/` — Soft PASS parallel-bus FFT metering (never on DAC path)
- `Services/MetadataLoader.swift` — Recursive folder scan, ID3/iTunes metadata extraction, playlist (m3u/pls) parsing and writing
- `Services/PersistenceManager.swift` — `@unchecked Sendable`; security-scoped folder bookmarks, JSON library cache, folder mtime
- `Models/Track.swift`, `Playlist.swift`, `PlaylistSeed.swift`, `RepeatMode.swift`, `SyncedLyricLine.swift`, `VisualizerMode.swift` — slim value types

### Views

- `Views/HomeView.swift` — Soft PASS Home: Continue, Recent, Playlists, Library shortcuts
- `Views/LibraryView.swift` — Track list with search; `TrackRow` and `NowPlayingBars` components live here
- `Views/NowPlayingView.swift` — Full-screen player with Soft PASS visualizer hero, ambient color, synced lyrics, seek bar
- `Views/PlaylistsView.swift` — Playlist list with creation/deletion; `PlaylistMosaicView` thumbnail component
- `Views/SmartPlaylistView.swift` — Make a Playlist Soft PASS (seeds → generate → preview → save)
- `Views/PlaylistDetailView.swift` — Playlist tracks with inline missing-file warnings; `AddTracksSheet`, `MissingTrackRow`
- `Views/MiniPlayerView.swift` — Compact bottom-bar player overlay
- `Views/SettingsView.swift` — Folder selection, rescan, stats
- `Components/DocumentPicker.swift` — `UIViewControllerRepresentable` wrapper for folder picker
- `Components/ArtworkView.swift` — async-loading artwork with placeholder
- `Components/Visualizers/` — Soft PASS Now Playing hero visualizer suite
## Key patterns

- Folder access uses security-scoped bookmarks (`PersistenceManager`); `AudioPlayerManager.startAccessingFolder()` must be active for file reads
- Playlists store `trackURLs: [URL]` and parallel `rawPaths: [String]` — always keep both in sync when mutating
- Library tracks are matched to playlist entries by comparing `.standardized` URLs
- Playlist files are rewritten atomically on every mutation via `MetadataLoader.writePlaylist()`
