import Foundation

/// Decides who gets a playback key on the Mac. The Playback menu binds
/// Space and Command-Left/Right, and menu key equivalents fire before the
/// focused text field sees the key, so typing a space in Search or Settings
/// would toggle playback and Command-arrows would skip tracks instead of
/// moving the caret. `MacPlaybackKeyMonitor` asks this first and hands
/// the key to the text field while one is being edited.
///
/// Platform-neutral so the unit tests (iOS-hosted) cover the decision.
enum PlaybackKeyRouting {
    enum Route: Equatable {
        /// Normal dispatch: the Playback menu handles it.
        case passThrough
        /// A text field is being edited: deliver the key there instead.
        case deliverToTextInput
    }

    static let spaceKeyCode: UInt16 = 49
    static let leftArrowKeyCode: UInt16 = 123
    static let rightArrowKeyCode: UInt16 = 124

    /// True for exactly the keys bound in the Playback menu.
    static func isPlaybackShortcut(
        keyCode: UInt16,
        command: Bool,
        option: Bool = false,
        control: Bool = false,
        shift: Bool = false
    ) -> Bool {
        guard !option, !control, !shift else { return false }
        switch keyCode {
        case spaceKeyCode: return !command
        case leftArrowKeyCode, rightArrowKeyCode: return command
        default: return false
        }
    }

    static func route(
        keyCode: UInt16,
        command: Bool,
        option: Bool = false,
        control: Bool = false,
        shift: Bool = false,
        isEditingText: Bool
    ) -> Route {
        guard isEditingText,
              isPlaybackShortcut(keyCode: keyCode, command: command, option: option,
                                 control: control, shift: shift)
        else { return .passThrough }
        return .deliverToTextInput
    }
}
