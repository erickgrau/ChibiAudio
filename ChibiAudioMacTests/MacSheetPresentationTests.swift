import AppKit
import SwiftUI
import XCTest
@testable import LocalMusic

/// Presents every sheet caller's content in a real AppKit window at the
/// minimum (960 x 600) and an enlarged (1440 x 900) size and measures the
/// sheet window AppKit attaches. Before the chibiSheet fix, Settings and Up
/// Next attached at 470 x 113 with only the title and Done visible.
///
/// Stores use a temporary documents folder and a throwaway defaults suite,
/// so the user's library, queue and settings are never read or written.
@MainActor
final class MacSheetPresentationTests: XCTestCase {

    private var tempDir: URL!
    private var player: AudioPlayerManager!
    private let library = LibraryStore()
    private let recents = RecentsStore(documentsURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("chibi-mac-tests-recents-\(UUID().uuidString)"))
    private let tabs = TabRouter()
    private let plus = PlusStore()

    private static let minimumWindow = NSSize(width: 960, height: 600)
    private static let enlargedWindow = NSSize(width: 1440, height: 900)

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("chibi-mac-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        player = makePlayer(queued: 4)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// A player restored from a temp queue.json: current track plus `queued`
    /// Up Next entries, without starting playback or touching Now Playing info.
    private func makePlayer(queued: Int) -> AudioPlayerManager {
        let defaults = UserDefaults(suiteName: "chibi-mac-tests-\(UUID().uuidString)")!
        let persistence = PersistenceManager(documentsURL: tempDir, userDefaults: defaults)
        if queued >= 0 {
            let tracks = (0...queued).map { i in
                Track(id: UUID(), url: URL(fileURLWithPath: "/nonexistent/chibi-test-\(i).m4a"),
                      title: "Queue Track \(i)", artist: "Test Artist", album: "Test Album",
                      duration: 200, hasArtwork: false, hasLyrics: false)
            }
            var queue = PlaybackQueue()
            _ = queue.play(track: tracks[0], queue: tracks, startIndex: 0)
            persistence.saveQueue(queue)
        }
        return AudioPlayerManager(persistence: persistence)
    }

    private var sampleTrack: Track {
        Track(id: UUID(), url: URL(fileURLWithPath: "/nonexistent/sample.m4a"),
              title: "Sample", artist: "Artist", album: "Album",
              duration: 180, hasArtwork: false, hasLyrics: false)
    }

    // MARK: - Harness

    /// Presents `content` through `chibiSheet` (or a plain `.sheet` when
    /// `useChibiSheet` is false) and returns the attached sheet window size.
    private func presentedSheetSize<Content: View>(
        in windowSize: NSSize = minimumWindow,
        size: ChibiSheetSize = .regular,
        useChibiSheet: Bool = true,
        player: AudioPlayerManager? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> NSSize? {
        let host = SheetHost(useChibiSheet: useChibiSheet, size: size, sheet: content)
            .environment(player ?? self.player)
            .environment(library)
            .environment(recents)
            .environment(tabs)
            .environment(plus)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: host)
        window.setContentSize(windowSize)
        window.makeKeyAndOrderFront(nil)

        let deadline = Date().addingTimeInterval(5)
        while window.attachedSheet == nil, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        // Let the sheet finish laying out at its final size.
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        let sheetSize = window.attachedSheet?.frame.size
        if let sheet = window.attachedSheet { window.endSheet(sheet) }
        window.orderOut(nil)
        window.close()
        if let sheetSize { print("SHEET-EVIDENCE \(name): window \(Int(windowSize.width))x\(Int(windowSize.height)) -> sheet \(Int(sheetSize.width))x\(Int(sheetSize.height))") }
        return sheetSize
    }

    private func assertUsable(_ measured: NSSize?, _ size: ChibiSheetSize, window: NSSize = minimumWindow,
                              file: StaticString = #filePath, line: UInt = #line) {
        guard let measured else {
            return XCTFail("No sheet attached", file: file, line: line)
        }
        XCTAssertGreaterThanOrEqual(measured.width, size.minWidth - 1, file: file, line: line)
        // Sheet window height includes its toolbar; content min height is the floor.
        XCTAssertGreaterThanOrEqual(measured.height, size.minHeight - 1, file: file, line: line)
        XCTAssertLessThanOrEqual(measured.width, window.width, "Sheet wider than its window", file: file, line: line)
    }

    // MARK: - Root cause (recorded, not asserted: depends on AppKit sizing)

    func testRootCause_plainSheetCollapsesUpNext() {
        let collapsed = presentedSheetSize(useChibiSheet: false) { UpNextView() }
        let fixed = presentedSheetSize { UpNextView() }
        print("SHEET-EVIDENCE root cause: plain .sheet Up Next = \(String(describing: collapsed)); chibiSheet = \(String(describing: fixed))")
        XCTAssertNotNil(fixed)
    }

    // MARK: - Every sheet caller

    func testSettingsSheet() {
        // iOS-style Settings sheet content (the Mac normally uses the Settings window).
        assertUsable(presentedSheetSize { SettingsView() }, .regular)
        assertUsable(presentedSheetSize(in: Self.enlargedWindow) { SettingsView() }, .regular, window: Self.enlargedWindow)
    }

    func testUpNextSheet_nonEmptyAndEmpty() {
        assertUsable(presentedSheetSize { UpNextView() }, .regular)
        let emptyPlayer = makePlayer(queued: -1)
        assertUsable(presentedSheetSize(player: emptyPlayer) { UpNextView() }, .regular)
        assertUsable(presentedSheetSize(in: Self.enlargedWindow) { UpNextView() }, .regular, window: Self.enlargedWindow)
    }

    func testLyricsSheet_emptyAndUnsynced() {
        let track = sampleTrack
        assertUsable(presentedSheetSize(size: .large) { LyricsSheet(track: track, lyrics: nil) }, .large)
        let text = TrackLyrics(unsynced: "First line\nSecond line", synced: nil)
        assertUsable(presentedSheetSize(size: .large) { LyricsSheet(track: track, lyrics: text) }, .large)
    }

    func testAddToPlaylistSheet() {
        let track = sampleTrack
        assertUsable(presentedSheetSize(size: .compact) { AddToPlaylistSheet(payload: .local(track)) }, .compact)
    }

    func testAddTracksSheet() {
        let playlist = Playlist(fileURL: tempDir.appendingPathComponent("Test.m3u"), name: "Test")
        assertUsable(presentedSheetSize { AddTracksSheet(playlist: .constant(playlist)) }, .regular)
    }

    func testSmartPlaylistSheet() {
        assertUsable(presentedSheetSize(size: .large) { SmartPlaylistView() }, .large)
    }

    func testPlexSignInSheet_signedOut() throws {
        try XCTSkipIf(PlexClient.shared.isSignedIn, "Signed-in Plex state would trigger a server refresh")
        assertUsable(presentedSheetSize(size: .compact) { PlexSignInView() }, .compact)
    }

    func testPaywallSheet() {
        assertUsable(presentedSheetSize(size: .large) { PaywallView() }, .large)
    }

    func testWhatsNewSheets() {
        assertUsable(presentedSheetSize(size: .large) {
            WhatsNewView(releases: Array(WhatsNew.all.prefix(1))) {}
        }, .large)
        assertUsable(presentedSheetSize(size: .large) {
            WhatsNewView(releases: WhatsNew.all, showsArchive: true) {}
        }, .large)
    }

    // MARK: - Settings window

    func testSettingsWindowPanesFitAtMinimumSize() {
        for pane in SettingsPane.allCases {
            let controller = NSHostingController(rootView:
                SettingsView(panes: [pane], isSettingsWindow: true)
                    .frame(minWidth: 560, minHeight: 440)
                    .environment(player).environment(library).environment(recents)
                    .environment(tabs).environment(plus)
            )
            let fitting = controller.view.fittingSize
            print("SHEET-EVIDENCE settings pane \(pane.rawValue): fitting \(Int(fitting.width))x\(Int(fitting.height))")
            XCTAssertGreaterThanOrEqual(fitting.height, 440, pane.title)
        }
    }
}

/// Presents `sheet` immediately, through chibiSheet or a plain sheet.
private struct SheetHost<Sheet: View>: View {
    let useChibiSheet: Bool
    let size: ChibiSheetSize
    @ViewBuilder let sheet: () -> Sheet
    @State private var isPresented = false

    var body: some View {
        let base = Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { isPresented = true }
        if useChibiSheet {
            base.chibiSheet(isPresented: $isPresented, size: size, content: sheet)
        } else {
            base.sheet(isPresented: $isPresented, content: sheet)
        }
    }
}
