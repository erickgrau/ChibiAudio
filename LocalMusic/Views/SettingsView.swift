import SwiftUI

struct SettingsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AudioPlayerManager.self) private var player

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
    @AppStorage(DACSession.dacModeDefaultsKey) private var dacModeEnabled = false
    @State private var plexServer = PlexClient.shared.serverURLString
    @State private var plexToken = PlexClient.shared.token
    private let crashService = CrashDiagnosticsService.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
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
                } header: {
                    Text("Music Folder")
                } footer: {
                    Text("Pick On My iPhone, app Documents, iCloud Drive, or Google Drive (install the Drive app and enable it under Files). Bookmarks persist; cloud files download-to-play when the provider supports it.")
                }

                Section {
                    Toggle("Hi-res / DAC mode", isOn: $dacModeEnabled)
                    LabeledContent("Output", value: player.audioRouteSummary)
                    NavigationLink("Equalizer") {
                        EqualizerView()
                    }
                } header: {
                    Text("Audio · THX Onyx")
                } footer: {
                    Text("Reference DAC: THX Onyx (ESS ES9281PRO). DAC mode maximizes preferred sample rate for USB and forces EQ off for a cleaner bit-perfect PCM path. MQA = hardware renderer on the Onyx — no software MQA decode in free ChibiAudio. DSD prefers DoP (encoder not in free v1 yet; never silent lossy fall-back).")
                }
                .onChange(of: dacModeEnabled) { _, _ in
                    player.reloadAudioSessionPreference()
                }

                Section {
                    TextField("Server URL (http://…:32400)", text: $plexServer)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("X-Plex-Token", text: $plexToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save Plex Settings") {
                        let client = PlexClient.shared
                        client.serverURLString = plexServer.trimmingCharacters(in: .whitespacesAndNewlines)
                        client.token = plexToken.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    NavigationLink("Browse Plex Music") {
                        PlexBrowserView()
                    }
                } header: {
                    Text("Plex")
                } footer: {
                    Text("Personal PMS only. Create a token at plex.tv/claim or from account XML. LAN direct play of your library works without Plex Pass; some remote features may need Pass.")
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
                        Text("ChibiAudio is a free fork of LocalMusic. Local/cloud folders and app-owned mixed playlists need no subscription. Apple Music catalog play (optional later) needs Apple Music.")
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
            .onAppear {
                plexServer = PlexClient.shared.serverURLString
                plexToken = PlexClient.shared.token
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
