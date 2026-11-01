import Foundation
import Testing
@testable import LocalMusic

/// Platform-neutral logic behind the Mac shell: playback key routing (so
/// Space never toggles playback while typing), album/artist grouping for
/// the browse views, Settings pane coverage, and Mac sheet sizing.
struct PlaybackKeyRoutingTests {
    typealias R = PlaybackKeyRouting

    @Test func spaceWhileEditingTextGoesToTheField() {
        #expect(R.route(keyCode: R.spaceKeyCode, command: false, isEditingText: true) == .deliverToTextInput)
    }

    @Test func spaceOutsideTextFieldsReachesPlaybackMenu() {
        #expect(R.route(keyCode: R.spaceKeyCode, command: false, isEditingText: false) == .passThrough)
    }

    @Test func commandArrowsWhileEditingMoveTheCaret() {
        #expect(R.route(keyCode: R.leftArrowKeyCode, command: true, isEditingText: true) == .deliverToTextInput)
        #expect(R.route(keyCode: R.rightArrowKeyCode, command: true, isEditingText: true) == .deliverToTextInput)
    }

    @Test func commandArrowsOutsideTextFieldsSkipTracks() {
        #expect(R.route(keyCode: R.leftArrowKeyCode, command: true, isEditingText: false) == .passThrough)
        #expect(R.route(keyCode: R.rightArrowKeyCode, command: true, isEditingText: false) == .passThrough)
    }

    @Test func onlyMenuBoundCombinationsAreIntercepted() {
        // Shift-Space, Command-Space, plain arrows and Option-Command-arrows
        // are not playback shortcuts, so the field handles them normally.
        #expect(!R.isPlaybackShortcut(keyCode: R.spaceKeyCode, command: false, shift: true))
        #expect(!R.isPlaybackShortcut(keyCode: R.spaceKeyCode, command: true))
        #expect(!R.isPlaybackShortcut(keyCode: R.leftArrowKeyCode, command: false))
        #expect(!R.isPlaybackShortcut(keyCode: R.rightArrowKeyCode, command: true, option: true))
        #expect(!R.isPlaybackShortcut(keyCode: 0, command: true)) // Command-A
        #expect(R.route(keyCode: R.spaceKeyCode, command: false, shift: true, isEditingText: true) == .passThrough)
    }
}

struct LibraryBrowseIndexTests {

    @Test func groupsAlbumsCaseInsensitivelyInFileOrder() {
        let tracks = [
            Fixtures.track(title: "B", artist: "Ann", album: "Blue", path: "/m/Blue/02 B.mp3", year: 2001),
            Fixtures.track(title: "A", artist: "Ann", album: "blue ", path: "/m/Blue/01 A.mp3", year: 2001),
            Fixtures.track(title: "C", artist: "Cy", album: "Alpha", path: "/m/Alpha/01 C.mp3"),
        ]
        let albums = LibraryBrowseIndex.albums(from: tracks)
        #expect(albums.map(\.title) == ["Alpha", "Blue"])
        let blue = try! #require(albums.last)
        #expect(blue.tracks.map(\.title) == ["A", "B"])
        #expect(blue.artist == "Ann")
        #expect(blue.year == 2001)
    }

    @Test func sameTitledAlbumsInDifferentFoldersStaySeparate() {
        let tracks = [
            Fixtures.track(title: "1", artist: "Ann", album: "Greatest Hits", path: "/m/Ann/Greatest Hits/01.mp3"),
            Fixtures.track(title: "2", artist: "Bo", album: "Greatest Hits", path: "/m/Bo/Greatest Hits/01.mp3"),
        ]
        let albums = LibraryBrowseIndex.albums(from: tracks)
        #expect(albums.count == 2)
        #expect(albums.map(\.artist) == ["Ann", "Bo"])
    }

    @Test func discSubfoldersStayOneAlbum() {
        let tracks = [
            Fixtures.track(title: "1", artist: "Ann", album: "Set", path: "/m/Set/CD1/01.mp3"),
            Fixtures.track(title: "2", artist: "Ann", album: "Set", path: "/m/Set/Disc 2/01.mp3"),
        ]
        #expect(LibraryBrowseIndex.albums(from: tracks).count == 1)
    }

    @Test func compilationsShowVariousArtists() {
        let tracks = [
            Fixtures.track(title: "1", artist: "Ann", album: "Mix", path: "/m/Mix/01.mp3"),
            Fixtures.track(title: "2", artist: "Bo", album: "Mix", path: "/m/Mix/02.mp3"),
        ]
        let albums = LibraryBrowseIndex.albums(from: tracks)
        #expect(albums.count == 1)
        #expect(albums.first?.artist == LibraryBrowseIndex.variousArtists)
    }

    @Test func artistsCountDistinctAlbums() {
        let tracks = [
            Fixtures.track(title: "1", artist: "Ann", album: "One", path: "/m/a1.mp3"),
            Fixtures.track(title: "2", artist: "ann", album: "Two", path: "/m/a2.mp3"),
            Fixtures.track(title: "3", artist: "Bo", album: "One", path: "/m/b1.mp3"),
        ]
        let artists = LibraryBrowseIndex.artists(from: tracks)
        #expect(artists.map(\.name) == ["Ann", "Bo"])
        #expect(artists.first?.albumCount == 2)
        #expect(artists.first?.tracks.count == 2)
    }

    @Test func emptyLibraryHasNoAlbumsOrArtists() {
        #expect(LibraryBrowseIndex.albums(from: []).isEmpty)
        #expect(LibraryBrowseIndex.artists(from: []).isEmpty)
    }

    @Test func blankTagsUseHonestFallbacks() {
        let tracks = [Fixtures.track(title: "x", artist: " ", album: "", path: "/m/x.mp3")]
        #expect(LibraryBrowseIndex.albums(from: tracks).first?.title == "Unknown Album")
        #expect(LibraryBrowseIndex.artists(from: tracks).first?.name == "Unknown Artist")
    }
}

struct MacShellLayoutTests {

    @Test func everySettingsPaneHasATitleAndIcon() {
        #expect(SettingsPane.allCases.count == 5)
        for pane in SettingsPane.allCases {
            #expect(!pane.title.isEmpty)
            #expect(!pane.systemImage.isEmpty)
        }
    }

    @Test func sheetsFitTheMinimumMacWindow() {
        // MacRootView's minimum window is 960 x 600; a sheet must fit under
        // the title bar at that size and never collapse to the toolbar.
        for size in [ChibiSheetSize.compact, .regular, .large] {
            #expect(size.minHeight >= 300)
            #expect(size.minHeight <= 548)
            #expect(size.minWidth <= 960)
            #expect(size.idealWidth >= size.minWidth)
            #expect(size.idealHeight >= size.minHeight)
        }
    }

    @Test func iOSTabsKeepTheirRawValues() {
        // Raw values are the iOS TabView tags; the Mac-only sections append.
        #expect(ChibiTab.home.rawValue == 0)
        #expect(ChibiTab.radio.rawValue == 4)
        #expect(ChibiTab.bandcamp.rawValue == 8)
    }
}
