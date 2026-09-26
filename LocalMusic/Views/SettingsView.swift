import SwiftUI

struct SettingsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AudioPlayerManager.self) private var player
    @Environment(PlusStore.self) private var plus
    @Environment(AppearanceStore.self) private var appearance
    @Bindable private var plex = PlexClient.shared

    private static let forkURL = URL(string: "https://github.com/erickgrau/ChibiAudio")!
    private static let upstreamURL = URL(string: "https://github.com/j23n/localmusic")!

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private var plexServerLabel: String {
        plex.discoveredServers.first(where: { $0.machineIdentifier == plex.machineIdentifier })?.name
            ?? (plex.serverURLString.isEmpty ? "Not selected" : "Library")
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var showFolderPicker = false
    @State private var showPaywall = false
    @AppStorage("crashReportingEnabled") private var crashReportingEnabled = false
    @AppStorage(DACSession.dacModeDefaultsKey) private var dacModeEnabled = false
    @State private var showPlexSignIn = false
    @State private var confirmPlexSignOut = false
    @State private var bandcampServer = BandcampSubsonicClient.shared.serverURLString
    @State private var bandcampUser = BandcampSubsonicClient.shared.username
    @State private var bandcampPassword = BandcampSubsonicClient.shared.password
    private let crashService = CrashDiagnosticsService.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if plus.isPlusActive {
                        Label("ChibiAudio Plus is active", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(ChibiTheme.teal)
                        Button("Manage Plus") { showPaywall = true }
                    } else {
                        Button {
                            showPaywall = true
                        } label: {
                            Label("Upgrade to Plus — \(plus.displayPrice)/mo", systemImage: "sparkles")
                        }
                        Button("Restore Purchases") {
                            Task { _ = await plus.restore() }
                        }
                    }
                } header: {
                    Text("ChibiAudio Plus")
                } footer: {
                    Text("Plus removes ads and unlocks all visualizer modes, plus CarPlay and Watch stubs. Local files, Plex, Radio Browser, and album/track art stay free.")
                }

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
                        .tint(ChibiTheme.teal)
                    DACRouteIndicator(
                        summary: player.audioRouteSummary,
                        isUSB: DACSession.currentRouteInfo().isUSBAudio
                    )
                    if dacModeEnabled && DACSession.currentRouteInfo().isUSBAudio {
                        BitPerfectOnyxPill()
                            .listRowBackground(Color.clear)
                    }
                    SampleRateChip(sampleRateHz: max(DACSession.currentRouteInfo().currentSampleRate, 44_100))
                        .listRowBackground(Color.clear)
                    NavigationLink {
                        EqualizerView()
                    } label: {
                        Label("Equalizer", systemImage: "slider.horizontal.3")
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
                    Picker("Appearance", selection: Binding(
                        get: { appearance.preference },
                        set: { appearance.preference = $0 }
                    )) {
                        ForEach(AppearancePreference.allCases) { pref in
                            Text(pref.label).tag(pref)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Light is the default. Dark is Onyx. System follows the device.")
                }

                Section {
                    if plex.isSignedIn {
                        LabeledContent("Signed in as", value: plex.username.isEmpty ? "Plex" : plex.username)
                        LabeledContent("Server", value: plexServerLabel)
                        NavigationLink("Browse Plex Music") {
                            PlexBrowserView()
                        }
                        Button("Sign out", role: .destructive) {
                            confirmPlexSignOut = true
                        }
                    } else {
                        Button("Continue with Plex") {
                            showPlexSignIn = true
                        }
                        NavigationLink("Browse Plex Music") {
                            PlexBrowserView()
                        }
                    }
                } header: {
                    Text("Plex")
                } footer: {
                    Text("Sign in with Plex. We never see your password. Personal music libraries only.")
                }

                Section {
                    TextField("Server URL", text: $bandcampServer)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Subsonic username", text: $bandcampUser)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Subsonic password", text: $bandcampPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save Bandcamp Settings") {
                        let client = BandcampSubsonicClient.shared
                        let trimmed = bandcampServer.trimmingCharacters(in: .whitespacesAndNewlines)
                        client.serverURLString = trimmed.isEmpty
                            ? BandcampSubsonicClient.defaultServerURL
                            : trimmed
                        client.username = bandcampUser.trimmingCharacters(in: .whitespacesAndNewlines)
                        client.password = bandcampPassword
                        bandcampServer = client.serverURLString
                    }
                    NavigationLink("Browse Bandcamp Collection") {
                        BandcampBrowserView()
                    }
                } header: {
                    Text("Bandcamp")
                } footer: {
                    Text("Official Subsonic API at \(BandcampSubsonicClient.defaultServerURL). Generate username and password in Bandcamp Fan Settings → Subsonic. Streams your purchased collection only — no HTML scraping.")
                }

                Section {
                    if CarPlayAudioTemplateStub.isUnlocked(isPlusActive: plus.isPlusActive) {
                        Label(CarPlayAudioTemplateStub.featureTitle, systemImage: "car.fill")
                        Text(CarPlayAudioTemplateStub.featureDetail)
                            .font(.footnote)
                            .foregroundStyle(ChibiTheme.textSecondary)
                        Text("Enable the CarPlay entitlement in Xcode when you are ready to ship — this repo does not invent Dist certs or entitlements.")
                            .font(.caption)
                            .foregroundStyle(ChibiTheme.textTertiary)
                    } else {
                        Button {
                            showPaywall = true
                        } label: {
                            Label("\(CarPlayAudioTemplateStub.featureTitle) — Plus", systemImage: "lock.fill")
                        }
                    }

                    if WatchCompanionStub.isUnlocked(isPlusActive: plus.isPlusActive) {
                        Label(WatchCompanionStub.featureTitle, systemImage: "applewatch")
                        Text(WatchCompanionStub.featureDetail)
                            .font(.footnote)
                            .foregroundStyle(ChibiTheme.textSecondary)
                    } else {
                        Button {
                            showPaywall = true
                        } label: {
                            Label("\(WatchCompanionStub.featureTitle) — Plus", systemImage: "lock.fill")
                        }
                    }
                } header: {
                    Text("CarPlay & Watch")
                } footer: {
                    Text("CarPlay uses Apple Audio templates only (large Now Playing art, browse, queue). Visualizers and vinyl/mixtape stay on iPhone and iPad — never on the dash.")
                }

                Section {
                    if plus.isPlusActive {
                        Text("Ads are off while Plus is active.")
                            .foregroundStyle(ChibiTheme.textSecondary)
                    } else if AdMobConfig.isConfigured {
                        Text("A free-tier banner may appear on Home, Library, Playlists, and Radio — never over Now Playing, DAC, or the visualizer.")
                            .foregroundStyle(ChibiTheme.textSecondary)
                    } else {
                        Text("Ads stay off until an AdMob app ID is configured (empty in CI builds).")
                            .foregroundStyle(ChibiTheme.textSecondary)
                    }
                } header: {
                    Text("Ads")
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
                        Text(AppBranding.tagline)
                            .font(.headline)
                            .foregroundStyle(ChibiTheme.textPrimary)
                        Text("ChibiAudio is a free fork of LocalMusic with optional Plus. Local/cloud folders, Plex, Radio Browser, and Bandcamp Subsonic need no Plus subscription. Apple Music catalog play (optional later) needs Apple Music.")
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
            .chibiListChrome()
            .toolbarBackground(ChibiTheme.softGlass, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .tint(ChibiTheme.amber)
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
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .onChange(of: crashReportingEnabled) { _, newValue in
                crashService.setEnabled(newValue)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { crashService.refreshPendingCrash() }
            }
            .onAppear {
                bandcampServer = BandcampSubsonicClient.shared.serverURLString
                bandcampUser = BandcampSubsonicClient.shared.username
                bandcampPassword = BandcampSubsonicClient.shared.password
            }
            .sheet(isPresented: $showPlexSignIn) {
                PlexSignInView()
            }
            .confirmationDialog("Disconnect Plex from ChibiAudio? This device forgets the sign-in.", isPresented: $confirmPlexSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    plex.signOut()
                }
                Button("Cancel", role: .cancel) {}
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
