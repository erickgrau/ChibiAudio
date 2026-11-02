#if os(macOS)
import AppKit
import SwiftUI

/// Window helpers for the Mac shell.
@MainActor
enum MacWindows {
    /// Brings the music window forward, e.g. after Settings jumps to a
    /// sidebar source. Returns false when no music window is open (the
    /// caller reopens one); the Settings window never counts.
    @discardableResult
    static func bringMainWindowForward() -> Bool {
        let main = NSApp.windows.first { window in
            window.canBecomeMain && window.isVisible
                && window.identifier?.rawValue.localizedCaseInsensitiveContains("settings") != true
        }
        main?.makeKeyAndOrderFront(nil)
        return main != nil
    }

    /// Settings tab to show next time the Settings window opens, so
    /// "Open Settings" from a source lands on the Sources pane.
    static let settingsPaneKey = "macSettingsPane"
}

/// Music folder selection shared by the sidebar, the File menu and Home.
@MainActor
enum MacFolderAccess {
    static func chooseFolder(library: LibraryStore) {
        DocumentPicker.pickFolder { pickerURL in
            _ = pickerURL.startAccessingSecurityScopedResource()
            PersistenceManager.shared.saveFolderBookmark(pickerURL)
            pickerURL.stopAccessingSecurityScopedResource()
            Task { await library.adoptSavedFolder() }
        }
    }
}

/// Keeps the Playback menu's Space and Command-Left/Right from stealing
/// keys while text is being edited (Library search, Settings fields,
/// playlist names). Local monitors run before menu key equivalents, so a
/// key bound in the menu is handed straight to the focused field editor
/// instead. Everywhere else the menu handles it as before.
@MainActor
enum MacPlaybackKeyMonitor {
    private static var monitor: Any?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let editor = event.window?.firstResponder as? NSTextView
            let route = PlaybackKeyRouting.route(
                keyCode: event.keyCode,
                command: flags.contains(.command),
                option: flags.contains(.option),
                control: flags.contains(.control),
                shift: flags.contains(.shift),
                isEditingText: editor?.isEditable == true
            )
            guard route == .deliverToTextInput, let editor else { return event }
            editor.keyDown(with: event)
            return nil
        }
    }
}
#endif
