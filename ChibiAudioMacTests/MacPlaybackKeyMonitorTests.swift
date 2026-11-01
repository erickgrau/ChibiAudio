import AppKit
import XCTest
@testable import LocalMusic

/// Drives real key events through NSApplication.sendEvent, where local
/// monitors and menu key equivalents run, with a probe menu item bound to
/// the same keys as the Playback menu. While a text field is being edited
/// the key must reach the field and the menu item must not fire; with no
/// text focus the menu item must fire.
@MainActor
final class MacPlaybackKeyMonitorTests: XCTestCase {

    private final class Probe: NSObject {
        var fired = 0
        @objc func fire(_ sender: Any?) { fired += 1 }
    }

    private var probe = Probe()
    private var probeMenu: NSMenuItem?
    private var window: NSWindow!
    private var field: NSTextField!

    override func setUp() async throws {
        MacPlaybackKeyMonitor.install()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 120),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        field = NSTextField(frame: NSRect(x: 20, y: 40, width: 360, height: 24))
        field.stringValue = "ab"
        window.contentView?.addSubview(field)
        window.makeKeyAndOrderFront(nil)
    }

    override func tearDown() async throws {
        if let probeMenu { NSApp.mainMenu?.removeItem(probeMenu) }
        window.close()
    }

    /// Adds a top-level menu with one item bound to `key` + `modifiers`.
    private func bindProbe(_ key: String, _ modifiers: NSEvent.ModifierFlags) {
        let item = NSMenuItem(title: "Probe", action: #selector(Probe.fire(_:)), keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = probe
        let submenu = NSMenu(title: "ProbeMenu")
        submenu.addItem(item)
        let top = NSMenuItem(title: "ProbeMenu", action: nil, keyEquivalent: "")
        top.submenu = submenu
        if NSApp.mainMenu == nil { NSApp.mainMenu = NSMenu() }
        NSApp.mainMenu?.addItem(top)
        probeMenu = top
    }

    private func send(_ keyCode: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags) {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: keyCode
        )!
        NSApp.sendEvent(event)
    }

    func testSpaceWhileTypingGoesIntoTheFieldNotTheMenu() throws {
        bindProbe(" ", [])
        XCTAssertTrue(window.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        send(PlaybackKeyRouting.spaceKeyCode, " ", [])
        XCTAssertEqual(probe.fired, 0, "Playback shortcut must not fire while typing")
        XCTAssertEqual(editor.string, "ab ", "The space should be typed into the field")
    }

    func testCommandLeftWhileTypingMovesCaretNotTrack() throws {
        let left = String(Character(UnicodeScalar(UInt16(NSLeftArrowFunctionKey))!))
        bindProbe(left, [.command])
        XCTAssertTrue(window.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        send(PlaybackKeyRouting.leftArrowKeyCode, left, [.command, .function, .numericPad])
        XCTAssertEqual(probe.fired, 0, "Previous Track must not fire while typing")
        XCTAssertEqual(editor.selectedRange().location, 0, "Command-Left should move the caret to line start")
    }

    /// The host app's real menu bar: Settings… on Command-comma, and the
    /// Playback menu's bindings that the monitor protects. (Pass-through
    /// with no text focus is covered by PlaybackKeyRoutingTests.)
    func testMenuBarExposesSettingsAndPlaybackShortcuts() throws {
        // SwiftUI builds the menu bar after launch; give it a moment.
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        let menu = try XCTUnwrap(NSApp.mainMenu)
        func items(_ m: NSMenu) -> [NSMenuItem] {
            m.items.flatMap { [$0] + ($0.submenu.map(items) ?? []) }
        }
        let all = items(menu)
        func find(_ title: String) -> NSMenuItem? { all.first { $0.title == title } }

        let settings = try XCTUnwrap(all.first { $0.title.hasPrefix("Settings") }, "Settings… menu item")
        XCTAssertEqual(settings.keyEquivalent, ",")
        XCTAssertEqual(settings.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask), .command)

        let playback = try XCTUnwrap(menu.items.first { $0.title == "Playback" }?.submenu, "Playback menu")
        let playPause = try XCTUnwrap(playback.items.first { $0.title == "Play" || $0.title == "Pause" })
        XCTAssertEqual(playPause.keyEquivalent, " ")
        XCTAssertEqual(find("Next Track")?.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask), .command)
        XCTAssertEqual(find("Previous Track")?.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask), .command)
        XCTAssertEqual(find("Show Up Next")?.keyEquivalent, "u")
        XCTAssertNotNil(find("Choose Music Folder…"))
        for title in ["Home", "Songs", "Albums", "Artists", "Playlists", "Radio", "Plex", "Bandcamp"] {
            XCTAssertNotNil(find(title), "View menu item \(title)")
        }
        print("MENU-EVIDENCE " + playback.items.map { "\($0.title)[\($0.keyEquivalent)]" }.joined(separator: ", "))
    }
}
