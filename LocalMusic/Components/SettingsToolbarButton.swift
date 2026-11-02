import SwiftUI

/// Gear button for Home and Library, with the pending-crash badge. iOS
/// presents Settings as a sheet; the Mac opens the Settings window (the
/// same window as ChibiAudio > Settings… and Command-comma).
struct SettingsToolbarButton: View {
    /// iOS: show the Settings sheet. Unused on the Mac.
    let showSettings: () -> Void
    @AppStorage("crashReportingEnabled") private var crashReportingEnabled = false
    private let crashService = CrashDiagnosticsService.shared

    var body: some View {
        #if os(macOS)
        SettingsLink { gear }
            .help("Settings")
        #else
        Button(action: showSettings) { gear }
        #endif
    }

    private var gear: some View {
        Image(systemName: "gear")
            .foregroundStyle(ChibiTheme.textPrimary)
            .overlay(alignment: .topTrailing) {
                if crashReportingEnabled, crashService.hasPendingCrash {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .offset(x: 4, y: -4)
                }
            }
            .accessibilityLabel(crashReportingEnabled && crashService.hasPendingCrash
                                ? "Settings, crash report pending" : "Settings")
    }
}
