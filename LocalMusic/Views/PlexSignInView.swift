import AuthenticationServices
import SwiftUI

/// Continue with Plex — PIN on Plex's page. Never collects a password.
struct PlexSignInView: View {
    @Bindable var client = PlexClient.shared
    @Environment(\.dismiss) private var dismiss
    @State private var advancedURL = ""
    @State private var showAdvanced = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if client.isSignedIn && !client.discoveredServers.isEmpty && client.serverURLString.isEmpty {
                        serverPicker
                    } else if client.isSigningIn, let code = client.pinCode {
                        pinBeat(code: code)
                    } else {
                        inviteBeat
                    }

                    if let err = client.lastError {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding(24)
            }
            .chibiCanvas()
            .navigationTitle("Plex")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        client.cancelSignIn()
                        dismiss()
                    }
                }
            }
            .task {
                if client.isSignedIn && client.discoveredServers.isEmpty {
                    await client.refreshAccountAndServers()
                }
            }
        }
    }

    private var inviteBeat: some View {
        VStack(alignment: .leading, spacing: 16) {
            SourceChip(kind: .plex)
            Text("Your Plex library. In ChibiAudio.")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(ChibiTheme.textPrimary)
            Text("Sign in with Plex. We never see your password.")
                .font(.body)
                .foregroundStyle(ChibiTheme.textSecondary)
            Button {
                Task { await startSignIn() }
            } label: {
                Text("Continue with Plex")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(ChibiTheme.amber)
            .controlSize(.large)
            Text("Personal music libraries only.")
                .font(.caption)
                .foregroundStyle(ChibiTheme.textTertiary)
        }
    }

    private func pinBeat(code: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Confirm this code on the Plex page.")
                .font(.title3.weight(.semibold))
                .foregroundStyle(ChibiTheme.textPrimary)
            Text(code)
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .tracking(4)
                .foregroundStyle(ChibiTheme.textPrimary)
            ProgressView()
            Button("Cancel", role: .cancel) {
                client.cancelSignIn()
            }
        }
    }

    private var serverPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a library")
                .font(ChibiTheme.titleFont())
                .foregroundStyle(ChibiTheme.textPrimary)
            ForEach(client.discoveredServers) { server in
                Button {
                    client.selectServer(server)
                    Task {
                        await client.refreshMusicLibraries()
                        dismiss()
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(server.name)
                                .font(.headline)
                                .foregroundStyle(ChibiTheme.textPrimary)
                            Text(PlexAuthService.connectionKind(server.preferredURI ?? "", connections: server.connections))
                                .font(.caption)
                                .foregroundStyle(ChibiTheme.teal)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(ChibiTheme.textTertiary)
                    }
                    .padding(16)
                    .chibiGlassCard(cornerRadius: 16)
                }
                .buttonStyle(.plain)
            }

            Button("Server didn’t show up") { showAdvanced = true }
                .font(.footnote)
                .foregroundStyle(ChibiTheme.textSecondary)

            if showAdvanced {
                TextField("Server address", text: $advancedURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button("Use this address") {
                    client.setAdvancedServerURL(advancedURL)
                    Task {
                        await client.refreshMusicLibraries()
                        dismiss()
                    }
                }
            }
        }
    }

    @MainActor
    private func startSignIn() async {
        guard let pin = await client.requestPin() else { return }
        guard let authURL = PlexAuthService.authPageURL(clientID: client.clientID, code: pin.code) else {
            client.lastError = "Couldn’t open Plex."
            client.isSigningIn = false
            return
        }
        client.startPolling(pin: pin)
        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "chibiaudio"
        ) { _, error in
            if error != nil {
                Task { @MainActor in
                    // Poll may still succeed; only cancel if no token yet.
                    if !PlexClient.shared.isSignedIn {
                        PlexClient.shared.cancelSignIn()
                    }
                }
            }
        }
        session.presentationContextProvider = PlexAuthPresenter.shared
        session.prefersEphemeralWebBrowserSession = false
        _ = session.start()
        PlexAuthPresenter.shared.retain(session)
    }
}

@MainActor
final class PlexAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = PlexAuthPresenter()
    private var session: ASWebAuthenticationSession?

    func retain(_ session: ASWebAuthenticationSession) {
        self.session = session
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
