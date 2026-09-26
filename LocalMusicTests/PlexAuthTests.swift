import Foundation
import Testing
@testable import LocalMusic

struct PlexAuthTests {

    @Test func parsePinJSON() throws {
        let data = Data(#"{"id": 42, "code": "ABCD"}"#.utf8)
        let pin = try PlexAuthService.parsePin(data)
        #expect(pin.id == 42)
        #expect(pin.code == "ABCD")
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

    @Test func authPageHasCallback() {
        let url = PlexAuthService.authPageURL(clientID: "cid", code: "ZZ")
        #expect(url?.host == "app.plex.tv")
        #expect(url?.fragment?.contains("code=ZZ") == true)
        #expect(url?.fragment?.contains("chibiaudio://plex-auth") == true)
    }
}
