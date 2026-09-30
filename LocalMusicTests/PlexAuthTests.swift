import AuthenticationServices
import Foundation
import Testing
@testable import LocalMusic

struct PlexAuthTests {

    /// Regression for the sheet that never closed: Plex's auth page doesn't
    /// reliably navigate to the forwardUrl, so the sign-in completion path
    /// must dismiss the sheet itself rather than rely on that callback.
    @MainActor
    @Test func dismissActiveSessionClearsRetainedSheet() {
        let session = ASWebAuthenticationSession(
            url: URL(string: "https://app.plex.tv/auth")!,
            callbackURLScheme: "chibiaudio"
        ) { _, _ in }
        PlexAuthPresenter.shared.retain(session)
        #expect(PlexAuthPresenter.shared.hasActiveSession)
        PlexAuthPresenter.shared.dismissActiveSession()
        #expect(!PlexAuthPresenter.shared.hasActiveSession)
    }

    @MainActor
    @Test func applyTokenDismissesTheAuthSheet() async {
        let session = ASWebAuthenticationSession(
            url: URL(string: "https://app.plex.tv/auth")!,
            callbackURLScheme: "chibiaudio"
        ) { _, _ in }
        PlexAuthPresenter.shared.retain(session)
        await PlexClient.shared.applyToken("test-token-\(UUID().uuidString)")
        #expect(!PlexAuthPresenter.shared.hasActiveSession)
        PlexClient.shared.signOut()
    }

    @Test func parsePinJSON() throws {
        let data = Data(#"{"id": 42, "code": "ABCD"}"#.utf8)
        let pin = try PlexAuthService.parsePin(data)
        #expect(pin.id == 42)
        #expect(pin.code == "ABCD")
    }

    /// Regression for the "pinBeat" bug: `strong=true` returns a ~25-char code
    /// meant for the silent app.plex.tv/auth flow, not the 4-char code the
    /// manual plex.tv/link page (linkPageURL) expects.
    @Test func pinsURLDoesNotRequestStrongCode() {
        #expect(PlexAuthService.pinsURL.query(percentEncoded: false) == nil)
    }

    @Test func parseAuthToken() {
        let data = Data(#"{"id": 1, "code": "X", "authToken": "tok_abc"}"#.utf8)
        #expect(PlexAuthService.parseAuthToken(data) == "tok_abc")
        let empty = Data(#"{"id": 1, "code": "X"}"#.utf8)
        #expect(PlexAuthService.parseAuthToken(empty) == nil)
    }

    @Test func preferredURIOrder() {
        let local = PlexAuthService.Connection(uri: "http://192.168.1.9:32400", local: true, relay: false)
        let https = PlexAuthService.Connection(uri: "https://1-2-3.plex.direct:32400", local: false, relay: false)
        let relay = PlexAuthService.Connection(uri: "https://relay.plex.tv", local: false, relay: true)
        #expect(PlexAuthService.bestURI(connections: [relay, https, local]) == local.uri)
        #expect(PlexAuthService.bestURI(connections: [relay, https]) == https.uri)
        #expect(PlexAuthService.bestURI(connections: [relay]) == relay.uri)
        #expect(PlexAuthService.connectionKind(local.uri, connections: [local]) == "On your network")
        #expect(PlexAuthService.connectionKind(relay.uri, connections: [relay]) == "Through Plex")
    }

    @Test func parseResourcesServersOnly() throws {
        let json = """
        [{"name":"Home","clientIdentifier":"abc","provides":"server","owned":true,
          "connections":[{"uri":"http://10.0.0.2:32400","local":true,"relay":false}]},
         {"name":"Phone","clientIdentifier":"phone","provides":"client","owned":true}]
        """
        let resources = try PlexAuthService.parseResources(Data(json.utf8))
        #expect(resources.count == 1)
        #expect(resources[0].name == "Home")
        #expect(resources[0].preferredURI == "http://10.0.0.2:32400")
    }

    @Test func linkPageIsManualCodeEntry() {
        // Regression: app.plex.tv/auth silently auto-authorizes against a
        // shared Safari session instead of asking the user to type the code.
        #expect(PlexAuthService.linkPageURL.host == "www.plex.tv")
        #expect(PlexAuthService.linkPageURL.path == "/link")
    }
}
