#if os(macOS)
import AppKit
import SwiftUI

/// Window helpers for the Mac shell.
@MainActor
enum MacWindows {
    /// Brings the main music window forward, e.g. after Settings jumps to a
    /// sidebar source. The main window is the one that can be main and is
    /// not the Settings panel.
    static func bringMainWindowForward() {
        let candidates = NSApp.windows.filter { $0.canBecomeMain && $0.isVisible }
        let main = candidates.first { !$0.isKeyWindow } ?? candidates.first
        main?.makeKeyAndOrderFront(nil)
    }
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
