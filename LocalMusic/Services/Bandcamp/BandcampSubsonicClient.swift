import CryptoKit
import Foundation

/// Bandcamp purchased-collection client via the official Subsonic / OpenSubsonic API.
///
/// Server: `https://bandcamp.com/api/subsonic`
/// Credentials: generate under Bandcamp → Fan Settings → Subsonic (not HTML scrape).
@Observable
@MainActor
final class BandcampSubsonicClient {

    static let shared = BandcampSubsonicClient()

    static let defaultServerURL = "https://bandcamp.com/api/subsonic"
    static let apiVersion = "1.16.0"
    static let clientName = "ChibiAudio"

    private static let serverURLKey = "bandcampSubsonicServerURL"
    private static let usernameKey = "bandcampSubsonicUsername"
    private static let passwordKey = "bandcampSubsonicPassword"

    var serverURLString: String {
        didSet { UserDefaults.standard.set(serverURLString, forKey: Self.serverURLKey) }
    }

    var username: String {
        didSet { UserDefaults.standard.set(username, forKey: Self.usernameKey) }
    }

    var password: String {
        didSet { UserDefaults.standard.set(password, forKey: Self.passwordKey) }
    }

    var lastError: String?
    var albums: [BandcampAlbum] = []
    var isLoading = false

    var isConfigured: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
            && !normalizedBase.isEmpty
    }

    private var normalizedBase: String {
        var s = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s.isEmpty ? Self.defaultServerURL : s
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.serverURLKey) ?? ""
        serverURLString = saved.isEmpty ? Self.defaultServerURL : saved
        username = UserDefaults.standard.string(forKey: Self.usernameKey) ?? ""
        password = UserDefaults.standard.string(forKey: Self.passwordKey) ?? ""
    }

    struct BandcampAlbum: Identifiable, Hashable, Sendable {
        var id: String
        var name: String
        var artist: String
        var coverArtID: String?
        var songCount: Int?
    }

    struct BandcampTrack: Identifiable, Hashable, Sendable {
        var id: String
        var title: String
        var artist: String
        var album: String
        var durationSeconds: Double
        var coverArtID: String?
    }

    func ping() async -> Bool {
        guard isConfigured else {
            lastError = "Enter your Bandcamp Subsonic username and password from Fan Settings."
            return false
        }
        lastError = nil
        do {
            let data = try await get("ping")
            let ok = try Self.statusOK(data)
            if !ok { lastError = try Self.errorMessage(data) ?? "Bandcamp Subsonic ping failed." }
            return ok
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func refreshCollection(size: Int = 200) async {
        guard isConfigured else {
            lastError = "Enter your Bandcamp Subsonic username and password from Fan Settings."
            return
        }
        isLoading = true
        defer { isLoading = false }
        lastError = nil
        do {
            let data = try await get("getAlbumList2", query: [
                URLQueryItem(name: "type", value: "alphabeticalByArtist"),
                URLQueryItem(name: "size", value: String(min(max(size, 1), 500))),
            ])
            guard try Self.statusOK(data) else {
                lastError = try Self.errorMessage(data) ?? "Couldn’t load Bandcamp collection."
                albums = []
                return
            }
            albums = try Self.parseAlbumList2(data)
        } catch {
            lastError = error.localizedDescription
            albums = []
            Log.library.error("Bandcamp album list failed: \(error.localizedDescription)")
        }
    }

    func fetchAlbumTracks(albumID: String) async -> [BandcampTrack] {
        guard isConfigured else { return [] }
        do {
            let data = try await get("getAlbum", query: [
                URLQueryItem(name: "id", value: albumID),
            ])
            guard try Self.statusOK(data) else {
                lastError = try Self.errorMessage(data) ?? "Couldn’t load album."
                return []
            }
            return try Self.parseAlbumSongs(data)
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    /// Direct stream URL for a purchased Bandcamp Subsonic song id.
    func streamURL(forSongID id: String) -> URL? {
        guard isConfigured else { return nil }
        return try? endpoint("stream", query: [
            URLQueryItem(name: "id", value: id),
        ], includeFormat: false)
    }

    // MARK: - HTTP

    private func get(_ action: String, query: [URLQueryItem] = []) async throws -> Data {
        let url = try endpoint(action, query: query)
        var request = URLRequest(url: url)
        request.setValue("\(Self.clientName)/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func endpoint(_ action: String, query: [URLQueryItem], includeFormat: Bool = true) throws -> URL {
        let pathAction = action.hasSuffix(".view") ? action : "\(action).view"
        let base = "\(normalizedBase)/rest/\(pathAction)"
        guard var components = URLComponents(string: base) else { throw URLError(.badURL) }

        let salt = Self.randomSalt()
        let token = Self.md5Hex(password + salt)

        var items = query
        items.append(URLQueryItem(name: "u", value: username.trimmingCharacters(in: .whitespacesAndNewlines)))
        items.append(URLQueryItem(name: "t", value: token))
        items.append(URLQueryItem(name: "s", value: salt))
        items.append(URLQueryItem(name: "v", value: Self.apiVersion))
        items.append(URLQueryItem(name: "c", value: Self.clientName))
        if includeFormat {
            items.append(URLQueryItem(name: "f", value: "json"))
        }
        components.queryItems = items
        guard let url = components.url else { throw URLError(.badURL) }
        return url
    }

    // MARK: - JSON parsing (testable)

    static func statusOK(_ data: Data) throws -> Bool {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = root["subsonic-response"] as? [String: Any],
              let status = response["status"] as? String else {
            return false
        }
        return status == "ok"
    }

    static func errorMessage(_ data: Data) throws -> String? {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = root["subsonic-response"] as? [String: Any],
              let error = response["error"] as? [String: Any] else {
            return nil
        }
        if let message = error["message"] as? String { return message }
        if let code = error["code"] {
            return "Bandcamp Subsonic error \(code)"
        }
        return nil
    }

    static func parseAlbumList2(_ data: Data) throws -> [BandcampAlbum] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = root["subsonic-response"] as? [String: Any] else {
            return []
        }
        let list = response["albumList2"] as? [String: Any]
        let rawAlbums = list?["album"]
        let array: [[String: Any]]
        if let many = rawAlbums as? [[String: Any]] {
            array = many
        } else if let one = rawAlbums as? [String: Any] {
            array = [one]
        } else {
            array = []
        }
        return array.compactMap { dict in
            guard let id = stringValue(dict["id"]),
                  let name = stringValue(dict["name"]) ?? stringValue(dict["title"]) else {
                return nil
            }
            return BandcampAlbum(
                id: id,
                name: name,
                artist: stringValue(dict["artist"]) ?? "Unknown Artist",
                coverArtID: stringValue(dict["coverArt"]),
                songCount: intValue(dict["songCount"])
            )
        }
    }

    static func parseAlbumSongs(_ data: Data) throws -> [BandcampTrack] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = root["subsonic-response"] as? [String: Any],
              let album = response["album"] as? [String: Any] else {
            return []
        }
        let albumName = stringValue(album["name"]) ?? stringValue(album["title"]) ?? "Album"
        let raw = album["song"]
        let songs: [[String: Any]]
        if let many = raw as? [[String: Any]] {
            songs = many
        } else if let one = raw as? [String: Any] {
            songs = [one]
        } else {
            songs = []
        }
        return songs.compactMap { dict in
            guard let id = stringValue(dict["id"]),
                  let title = stringValue(dict["title"]) else { return nil }
            let duration: Double
            if let d = dict["duration"] as? Double {
                duration = d
            } else if let i = dict["duration"] as? Int {
                duration = Double(i)
            } else if let s = dict["duration"] as? String, let v = Double(s) {
                duration = v
            } else {
                duration = 0
            }
            return BandcampTrack(
                id: id,
                title: title,
                artist: stringValue(dict["artist"]) ?? "Unknown Artist",
                album: stringValue(dict["album"]) ?? albumName,
                durationSeconds: duration,
                coverArtID: stringValue(dict["coverArt"])
            )
        }
    }

    private static func stringValue(_ any: Any?) -> String? {
        if let s = any as? String { return s }
        if let i = any as? Int { return String(i) }
        if let n = any as? NSNumber { return n.stringValue }
        return nil
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String { return Int(s) }
        return nil
    }

    private static func randomSalt(length: Int = 12) -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    private static func md5Hex(_ string: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
