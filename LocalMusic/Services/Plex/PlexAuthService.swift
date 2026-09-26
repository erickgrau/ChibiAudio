import Foundation

/// Official Plex PIN sign-in (legacy strong PIN). Never collects a password.
enum PlexAuthService {
    static let productName = "ChibiAudio"
    static let callbackURL = "chibiaudio://plex-auth"
    static let pinsURL = URL(string: "https://plex.tv/api/v2/pins?strong=true")!

    struct Pin: Equatable, Sendable {
        var id: Int
        var code: String
    }

    struct Resource: Equatable, Sendable, Identifiable {
        var id: String { machineIdentifier }
        var name: String
        var machineIdentifier: String
        var owned: Bool
        var connections: [Connection]
        var preferredURI: String? { PlexAuthService.bestURI(connections: connections) }
    }

    struct Connection: Equatable, Sendable {
        var uri: String
        var local: Bool
        var relay: Bool
    }

    static func plexHeaders(clientID: String, token: String? = nil) -> [String: String] {
        var headers = [
            "Accept": "application/json",
            "X-Plex-Product": productName,
            "X-Plex-Client-Identifier": clientID,
            "X-Plex-Platform": "iOS",
            "X-Plex-Device-Name": "ChibiAudio",
            "X-Plex-Version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0",
        ]
        if let token, !token.isEmpty {
            headers["X-Plex-Token"] = token
        }
        return headers
    }

    static func authPageURL(clientID: String, code: String) -> URL? {
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = "app.plex.tv"
        parts.path = "/auth"
        parts.fragment = [
            "clientID=\(clientID)",
            "code=\(code)",
            "context[device][product]=\(productName)",
            "forwardUrl=\(callbackURL)",
        ].joined(separator: "&")
        return parts.url
    }

    static func parsePin(_ data: Data) throws -> Pin {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = intValue(json["id"]),
              let code = json["code"] as? String, !code.isEmpty else {
            throw URLError(.cannotParseResponse)
        }
        return Pin(id: id, code: code)
    }

    static func parseAuthToken(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let token = json["authToken"] as? String, !token.isEmpty { return token }
        return nil
    }

    static func parseResources(_ data: Data) throws -> [Resource] {
        let root = try JSONSerialization.jsonObject(with: data)
        let rows: [[String: Any]]
        if let array = root as? [[String: Any]] {
            rows = array
        } else if let dict = root as? [String: Any],
                  let inner = dict["MediaContainer"] as? [String: Any],
                  let devices = inner["Device"] as? [[String: Any]] {
            rows = devices
        } else {
            rows = []
        }

        return rows.compactMap { dict in
            let provides = (dict["provides"] as? String) ?? ""
            let isServer = provides.contains("server")
                || (dict["product"] as? String)?.localizedCaseInsensitiveContains("media server") == true
            guard isServer else { return nil }
            guard let machine = (dict["clientIdentifier"] as? String) ?? (dict["machineIdentifier"] as? String),
                  !machine.isEmpty else { return nil }
            let name = (dict["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Plex Server"
            let owned = boolValue(dict["owned"]) ?? true
            let connections = parseConnections(dict["connections"] ?? dict["Connection"])
            return Resource(
                name: name,
                machineIdentifier: machine,
                owned: owned,
                connections: connections
            )
        }
    }

    static func bestURI(connections: [Connection]) -> String? {
        if let local = connections.first(where: { $0.local && !$0.relay }) {
            return local.uri
        }
        if let publicHTTPS = connections.first(where: {
            !$0.relay && $0.uri.lowercased().hasPrefix("https://")
        }) {
            return publicHTTPS.uri
        }
        if let nonRelay = connections.first(where: { !$0.relay }) {
            return nonRelay.uri
        }
        return connections.first?.uri
    }

    static func connectionKind(_ uri: String, connections: [Connection]) -> String {
        guard let match = connections.first(where: { $0.uri == uri }) else { return "Remote" }
        if match.local && !match.relay { return "On your network" }
        if match.relay { return "Through Plex" }
        return "Remote"
    }

    private static func parseConnections(_ any: Any?) -> [Connection] {
        let rows: [[String: Any]]
        if let many = any as? [[String: Any]] {
            rows = many
        } else if let one = any as? [String: Any] {
            rows = [one]
        } else {
            rows = []
        }
        return rows.compactMap { dict in
            let uri = (dict["uri"] as? String) ?? (dict["address"] as? String)
            guard let uri, !uri.isEmpty else { return nil }
            return Connection(
                uri: uri,
                local: boolValue(dict["local"]) ?? false,
                relay: boolValue(dict["relay"]) ?? false
            )
        }
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String { return Int(s) }
        return nil
    }

    private static func boolValue(_ any: Any?) -> Bool? {
        if let b = any as? Bool { return b }
        if let n = any as? NSNumber { return n.boolValue }
        if let i = any as? Int { return i != 0 }
        if let s = any as? String {
            return s == "1" || s.lowercased() == "true"
        }
        return nil
    }
}
