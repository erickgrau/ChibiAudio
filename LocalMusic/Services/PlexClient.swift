import AVFoundation
import Foundation
import Observation

/// Plex client: PIN account on plex.tv, then personal music libraries on PMS.
@Observable
@MainActor
final class PlexClient {

    static let shared = PlexClient()

    private static let serverURLKey = "plexServerURL"
    private static let machineKey = "plexMachineIdentifier"
    private static let usernameKey = "plexUsername"
    private static let legacyTokenKey = "plexToken"

    var serverURLString: String {
        didSet { UserDefaults.standard.set(serverURLString, forKey: Self.serverURLKey) }
    }

    var machineIdentifier: String {
        didSet { UserDefaults.standard.set(machineIdentifier, forKey: Self.machineKey) }
    }

    var username: String {
        didSet { UserDefaults.standard.set(username, forKey: Self.usernameKey) }
    }

    var lastError: String?
    var musicSections: [PlexDirectory] = []
    var discoveredServers: [PlexAuthService.Resource] = []
    var pinCode: String?
    var isSigningIn = false

    private var pollTask: Task<Void, Never>?

    var authToken: String? {
        PlexKeychain.load(PlexKeychain.tokenAccount)
    }

    var clientID: String {
        PlexKeychain.clientIdentifier()
    }

    var isSignedIn: Bool {
        !(authToken ?? "").isEmpty
    }

    var isConfigured: Bool {
        isSignedIn && !serverURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var connectionKindLabel: String {
        guard let resource = discoveredServers.first(where: { $0.machineIdentifier == machineIdentifier }),
              let uri = resource.preferredURI else { return "Remote" }
        return PlexAuthService.connectionKind(uri, connections: resource.connections)
    }

    private init() {
        serverURLString = UserDefaults.standard.string(forKey: Self.serverURLKey) ?? ""
        machineIdentifier = UserDefaults.standard.string(forKey: Self.machineKey) ?? ""
        username = UserDefaults.standard.string(forKey: Self.usernameKey) ?? ""
        migrateLegacyTokenIfNeeded()
    }

    struct PlexDirectory: Identifiable, Hashable, Sendable {
        var id: String { key }
        var key: String
        var title: String
        var type: String
        var thumb: String?
    }

    struct PlexAlbum: Identifiable, Hashable, Sendable {
        var id: String { ratingKey }
        var ratingKey: String
        var title: String
        var artist: String
        var thumb: String?
        var year: Int?
    }

    struct PlexTrack: Identifiable, Hashable, Sendable {
        var id: String { ratingKey }
        var ratingKey: String
        var title: String
        var artist: String
        var album: String
        var durationMs: Double
        var thumb: String?
    }

    // MARK: - Sign in

    func requestPin() async -> PlexAuthService.Pin? {
        lastError = nil
        isSigningIn = true
        pinCode = nil
        var request = URLRequest(url: PlexAuthService.pinsURL)
        request.httpMethod = "POST"
        for (k, v) in PlexAuthService.plexHeaders(clientID: clientID) {
            request.setValue(v, forHTTPHeaderField: k)
        }
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let pin = try PlexAuthService.parsePin(data)
            pinCode = pin.code
            return pin
        } catch {
            lastError = "Couldn’t start Plex sign-in. Try again."
            isSigningIn = false
            Log.library.error("Plex pin create failed: \(error.localizedDescription)")
            return nil
        }
    }

    func startPolling(pin: PlexAuthService.Pin) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<80 {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if Task.isCancelled { return }
                if await self.pollPinOnce(id: pin.id) { return }
            }
            await MainActor.run {
                self.lastError = "Sign-in timed out. Try again."
                self.isSigningIn = false
                self.pinCode = nil
            }
        }
    }

    func cancelSignIn() {
        pollTask?.cancel()
        pollTask = nil
        isSigningIn = false
        pinCode = nil
    }

    func signOut() {
        cancelSignIn()
        PlexKeychain.delete(PlexKeychain.tokenAccount)
        UserDefaults.standard.removeObject(forKey: Self.legacyTokenKey)
        serverURLString = ""
        machineIdentifier = ""
        username = ""
        musicSections = []
        discoveredServers = []
        lastError = nil
    }

    func applyToken(_ token: String) async {
        PlexKeychain.save(token, account: PlexKeychain.tokenAccount)
        UserDefaults.standard.removeObject(forKey: Self.legacyTokenKey)
        pinCode = nil
        isSigningIn = false
        await refreshAccountAndServers()
    }

    func selectServer(_ resource: PlexAuthService.Resource, customURI: String? = nil) {
        machineIdentifier = resource.machineIdentifier
        if let customURI, !customURI.isEmpty {
            serverURLString = customURI.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else if let uri = resource.preferredURI {
            serverURLString = uri.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
    }

    func setAdvancedServerURL(_ url: String) {
        serverURLString = url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    func refreshAccountAndServers() async {
        guard let token = authToken, !token.isEmpty else { return }
        lastError = nil
        do {
            let url = URL(string: "https://plex.tv/api/v2/resources?includeHttps=1&includeRelay=1")!
            var request = URLRequest(url: url)
            for (k, v) in PlexAuthService.plexHeaders(clientID: clientID, token: token) {
                request.setValue(v, forHTTPHeaderField: k)
            }
            let (data, _) = try await URLSession.shared.data(for: request)
            let servers = try PlexAuthService.parseResources(data)
            discoveredServers = servers
            if username.isEmpty {
                username = "Plex"
            }
            if serverURLString.isEmpty, let first = servers.first {
                selectServer(first)
            }
        } catch {
            lastError = error.localizedDescription
            Log.library.error("Plex resources failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Library

    func refreshMusicLibraries() async {
        guard isConfigured else {
            lastError = "Sign in with Plex to browse your library."
            return
        }
        lastError = nil
        do {
            let url = try endpoint("/library/sections")
            let data = try await authorizedData(url)
            let all = try Self.parseDirectories(data)
            let music = all.filter { $0.type == "artist" }
            musicSections = music.isEmpty ? all : music
        } catch {
            lastError = error.localizedDescription
            Log.library.error("Plex sections failed: \(error.localizedDescription)")
        }
    }

    func fetchAlbums(sectionKey: String) async -> [PlexAlbum] {
        guard isConfigured else { return [] }
        do {
            let url = try endpoint("/library/sections/\(sectionKey)/all", query: [
                URLQueryItem(name: "type", value: "9"),
                URLQueryItem(name: "sort", value: "originallyAvailableAt:desc"),
            ])
            let data = try await authorizedData(url)
            return try Self.parseAlbums(data)
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    func fetchAlbumTracks(ratingKey: String) async -> [PlexTrack] {
        guard isConfigured else { return [] }
        do {
            let url = try endpoint("/library/metadata/\(ratingKey)/children")
            let data = try await authorizedData(url)
            return try Self.parseTracks(data)
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    func fetchTracks(sectionKey: String) async -> [PlexTrack] {
        guard isConfigured else { return [] }
        do {
            let url = try endpoint("/library/sections/\(sectionKey)/all", query: [
                URLQueryItem(name: "type", value: "10"),
            ])
            let data = try await authorizedData(url)
            return try Self.parseTracks(data)
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    /// Playback URL without the token in the query string.
    func directPlayURL(serverURL: String, ratingKey: String) -> URL? {
        let base = serverURLString.isEmpty ? serverURL : serverURLString
        guard !base.isEmpty, isSignedIn else { return nil }
        let trimmed = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(trimmed)/library/metadata/\(ratingKey)/stream?download=0")
    }

    func authorizedAsset(url: URL) -> AVURLAsset {
        var headers: [String: String] = [:]
        if let token = authToken {
            headers = PlexAuthService.plexHeaders(clientID: clientID, token: token)
        }
        return AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
    }

    func artworkURL(thumb: String?) -> URL? {
        guard let thumb, !thumb.isEmpty, isConfigured else { return nil }
        if thumb.hasPrefix("http") { return URL(string: thumb) }
        let base = serverURLString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = thumb.hasPrefix("/") ? thumb : "/\(thumb)"
        return URL(string: base + path)
    }

    // MARK: - HTTP

    private func pollPinOnce(id: Int) async -> Bool {
        guard let url = URL(string: "https://plex.tv/api/v2/pins/\(id)") else { return false }
        var request = URLRequest(url: url)
        for (k, v) in PlexAuthService.plexHeaders(clientID: clientID) {
            request.setValue(v, forHTTPHeaderField: k)
        }
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let token = PlexAuthService.parseAuthToken(data) {
                await applyToken(token)
                return true
            }
        } catch {
            Log.library.debug("Plex pin poll: \(error.localizedDescription)")
        }
        return false
    }

    private func authorizedData(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        for (k, v) in PlexAuthService.plexHeaders(clientID: clientID, token: authToken) {
            request.setValue(v, forHTTPHeaderField: k)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func endpoint(_ path: String, query: [URLQueryItem] = []) throws -> URL {
        let trimmed = serverURLString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(string: trimmed + path) else {
            throw URLError(.badURL)
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else { throw URLError(.badURL) }
        return url
    }

    private func migrateLegacyTokenIfNeeded() {
        guard authToken == nil,
              let legacy = UserDefaults.standard.string(forKey: Self.legacyTokenKey),
              !legacy.isEmpty else { return }
        PlexKeychain.save(legacy, account: PlexKeychain.tokenAccount)
        UserDefaults.standard.removeObject(forKey: Self.legacyTokenKey)
    }

    // MARK: - JSON

    private static func mediaContainer(_ data: Data) throws -> [String: Any] {
        let root = try JSONSerialization.jsonObject(with: data)
        if let dict = root as? [String: Any] {
            if let mc = dict["MediaContainer"] as? [String: Any] { return mc }
            return dict
        }
        return [:]
    }

    private static func array(_ any: Any?) -> [[String: Any]] {
        if let many = any as? [[String: Any]] { return many }
        if let one = any as? [String: Any] { return [one] }
        return []
    }

    private static func parseDirectories(_ data: Data) throws -> [PlexDirectory] {
        let mc = try mediaContainer(data)
        return array(mc["Directory"]).compactMap { dict in
            guard let key = stringValue(dict["key"]),
                  let title = stringValue(dict["title"]) else { return nil }
            return PlexDirectory(
                key: key,
                title: title,
                type: stringValue(dict["type"]) ?? "",
                thumb: stringValue(dict["thumb"])
            )
        }
    }

    private static func parseAlbums(_ data: Data) throws -> [PlexAlbum] {
        let mc = try mediaContainer(data)
        let rows = array(mc["Metadata"]).isEmpty ? array(mc["Directory"]) : array(mc["Metadata"])
        return rows.compactMap { dict in
            guard let ratingKey = stringValue(dict["ratingKey"]) ?? stringValue(dict["key"]),
                  let title = stringValue(dict["title"]) else { return nil }
            return PlexAlbum(
                ratingKey: ratingKey,
                title: title,
                artist: stringValue(dict["parentTitle"]) ?? stringValue(dict["originalTitle"]) ?? "Unknown Artist",
                thumb: stringValue(dict["thumb"]),
                year: intValue(dict["year"])
            )
        }
    }

    private static func parseTracks(_ data: Data) throws -> [PlexTrack] {
        let mc = try mediaContainer(data)
        return array(mc["Metadata"]).compactMap { dict in
            guard let ratingKey = stringValue(dict["ratingKey"]) ?? stringValue(dict["key"]),
                  let title = stringValue(dict["title"]) else { return nil }
            let durationMs = doubleValue(dict["duration"]) ?? 0
            return PlexTrack(
                ratingKey: ratingKey,
                title: title,
                artist: stringValue(dict["grandparentTitle"]) ?? stringValue(dict["originalTitle"]) ?? "Unknown Artist",
                album: stringValue(dict["parentTitle"]) ?? "Unknown Album",
                durationMs: durationMs,
                thumb: stringValue(dict["thumb"])
            )
        }
    }

    private static func stringValue(_ any: Any?) -> String? {
        if let s = any as? String, !s.isEmpty { return s }
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

    private static func doubleValue(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String { return Double(s) }
        return nil
    }
}
