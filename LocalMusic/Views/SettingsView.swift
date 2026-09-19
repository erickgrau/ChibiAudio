import SwiftUI

struct SettingsView: View {
    @Environment(LibraryStore.self) private var library

    private static let forkURL = URL(string: "https://github.com/erickgrau/ChibiAudio")!
    private static let upstreamURL = URL(string: "https://github.com/j23n/localmusic")!

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var showFolderPicker = false
    @AppStorage("crashReportingEnabled") private var crashReportingEnabled = false
    private let crashService = CrashDiagnosticsService.shared

    var body: some View {
        NavigationStack {
            List {
                Section("Music Folder") {
                    Button {
                        showFolderPicker = true
                    } label: {
                        LabeledContent {
                            Text(library.folderURL?.lastPathComponent ?? "Not selected")
                                .foregroundStyle(.secondary)
                        } label: {
                            Label("Folder", systemImage: "folder")
                        }
                    }
                    .tint(.primary)

                    Button {
                        Task { await library.rescan() }
                    } label: {
                        Label("Reload Music", systemImage: "arrow.clockwise")
                    }
                    .disabled(library.folderURL == nil || library.isScanning)

                    if let lastSynced = library.lastSynced {
                        LabeledContent("Last Synced", value: lastSynced, format: .dateTime)
                    }

                    if library.isScanning {
                        if let progress = library.scanProgress, progress.total > 0 {
                            VStack(alignment: .leading, spacing: 4) {
                                ProgressView(value: Double(progress.completed),
                                             total: Double(max(progress.total, 1)))
                                Text("Scanning \(progress.completed) of \(progress.total)…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        } else {
                            HStack {
                                ProgressView()
                                Text("Scanning folder…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Stats") {
                    LabeledContent("Total Songs", value: "\(library.tracks.count)")
                    LabeledContent("Total Playlists", value: "\(library.playlists.count)")
                }

                Section {
                    Toggle("Crash Reporting", isOn: $crashReportingEnabled)
                } header: {
                    Text("Crash Reporting")
                } footer: {
                    Text("When on, ChibiAudio captures crash details and recent log entries on this device. Nothing is sent automatically — if a crash is captured, a banner appears here in Settings and you can choose to share the report with the developer. Logs include file names and folder paths from your library. Off by default. App Store crash analytics (system-level) are unaffected by this setting.")
                }

                if crashReportingEnabled, crashService.hasPendingCrash {
                    crashSection
                }

                Section("Diagnostics") {
                    NavigationLink {
                        LogsView()
                    } label: {
                        Label("Logs", systemImage: "doc.text.magnifyingglass")
                    }
                    LabeledContent("Version", value: appVersion)
                }

                Section("About") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ChibiAudio is a fork of LocalMusic. Local and cloud folders are primary; free internet radio is built-in. Apple Music catalogue search is optional and requires a paid Apple Music subscription.")
                            .font(.callout)

                        Text("Based on open-source LocalMusic (MPL-2.0). Found a bug or have feedback?")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    Button {
                        openURL(Self.forkURL)
                    } label: {
                        LabeledContent {
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } label: {
                            Label("ChibiAudio on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                    }
                    .tint(.primary)

                    Button {
                        openURL(Self.upstreamURL)
                    } label: {
                        LabeledContent {
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } label: {
                            Label("Upstream LocalMusic", systemImage: "link")
                        }
                    }
                    .tint(.primary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showFolderPicker) {
                DocumentPicker { pickerURL in
                    // The picker's URL carries a transient security scope that
                    // must be claimed and turned into a bookmark synchronously
                    // here; the rescan can then run as a Task.
                    _ = pickerURL.startAccessingSecurityScopedResource()
                    PersistenceManager.shared.saveFolderBookmark(pickerURL)
                    pickerURL.stopAccessingSecurityScopedResource()
                    Task {
                        await library.adoptSavedFolder()
                    }
                }
            }
            .onChange(of: crashReportingEnabled) { _, newValue in
                crashService.setEnabled(newValue)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { crashService.refreshPendingCrash() }
            }
        }
    }

    @ViewBuilder
    private var crashSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("ChibiAudio crashed last session", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("A crash report was captured. You can share it with the developer to help diagnose the issue, or dismiss it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            Button {
                shareCrashReport()
            } label: {
                Label("Share Crash Report", systemImage: "square.and.arrow.up")
            }

            Button(role: .destructive) {
                crashService.clearPendingCrash()
            } label: {
                Label("Dismiss", systemImage: "xmark.circle")
            }
        }
    }

    private func shareCrashReport() {
        let stamp = Date().formatted(.iso8601.year().month().day())
        var items: [Any] = []

        if let data = crashService.pendingCrashReport() {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("chibiaudio-crash-\(stamp).json")
            if (try? data.write(to: url, options: .atomic)) != nil {
                items.append(url)
            }
        }

        if let data = crashService.recentLogTail() {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("chibiaudio-logs-\(stamp).txt")
            if (try? data.write(to: url, options: .atomic)) != nil {
                items.append(url)
            }
        }

        guard !items.isEmpty else { return }
        ShareSheet.present(items: items)
    }
}
