import Foundation

/// Free MusicBrainz + ListenBrainz HTTP helpers for optional related-artist /
/// tag enrichment. Always optional — playlist generation works offline.
///
/// Etiquette (https://musicbrainz.org/doc/MusicBrainz_API/Rate_Limiting):
/// - Speak `User-Agent: ChibiAudio/… (…)`
/// - Stay under ~1 request/second
/// - Cache results briefly
actor MusicCatalogClient {

    static let shared = MusicCatalogClient()

    private static let userAgent = "ChibiAudio/1.0 (https://github.com/erickgrau/ChibiAudio)"
    private static let listenBrainzBase = URL(string: "https://api.listenbrainz.org/1")!
    private static let minInterval: TimeInterval = 1.05
    private static let cacheTTL: TimeInterval = 6 * 60 * 60

    private var lastRequestAt: Date = .distantPast
    private var relatedCache: [String: (date: Date, artists: [String])] = [:]
    private var tagsCache: [String: (date: Date, tags: [String])] = [:]

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        config.httpAdditionalHeaders = [
            "User-Agent": MusicCatalogClient.userAgent,
            "Accept": "application/json",
        ]
        return URLSession(configuration: config)
    }()

    /// Related artist names for a seed artist (MusicBrainz artist-rels + ListenBrainz similar).
    func relatedArtists(forArtist name: String, limit: Int = 8) async -> [String] {
        let key = PlaylistScoringEngine.normalize(name)
        guard !key.isEmpty else { return [] }

        if let cached = relatedCache[key],
           Date().timeIntervalSince(cached.date) < Self.cacheTTL {
            return Array(cached.artists.prefix(limit))
        }

        var related: [String] = []
        if let mb = await musicBrainzRelatedArtists(named: name) {
            related.append(contentsOf: mb)
        }
        if related.count < limit, let lb = await listenBrainzSimilarArtists(named: name) {
            related.append(contentsOf: lb)
        }

        // Dedupe preserving order.
        var seen = Set<String>()
        let unique = related.compactMap { raw -> String? in
            let n = PlaylistScoringEngine.normalize(raw)
            guard !n.isEmpty, n != key, seen.insert(n).inserted else { return nil }
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        relatedCache[key] = (Date(), unique)
        return Array(unique.prefix(limit))
    }

    /// Tags / genres associated with an artist (MusicBrainz).
    func tags(forArtist name: String, limit: Int = 6) async -> [String] {
        let key = PlaylistScoringEngine.normalize(name)
        guard !key.isEmpty else { return [] }
        if let cached = tagsCache[key],
           Date().timeIntervalSince(cached.date) < Self.cacheTTL {
            return Array(cached.tags.prefix(limit))
        }
        let tags = await musicBrainzTags(named: name)
        tagsCache[key] = (Date(), tags)
        return Array(tags.prefix(limit))
    }

    /// Gather related artists across a set of seed artist names (rate-limited).
    func relatedArtists(forArtists names: [String], perArtist: Int = 5) async -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for name in names {
            let related = await relatedArtists(forArtist: name, limit: perArtist)
            for r in related {
                let key = PlaylistScoringEngine.normalize(r)
                if seen.insert(key).inserted {
                    out.append(r)
                }
            }
        }
        return out
    }

    // MARK: - MusicBrainz

    private func musicBrainzRelatedArtists(named name: String) async -> [String]? {
        guard let mbid = await musicBrainzArtistID(named: name) else { return nil }
        do {
            let data = try await get(
                URL(string: "https://musicbrainz.org/ws/2/artist/\(mbid)")!,
                query: [
                    URLQueryItem(name: "inc", value: "artist-rels"),
                    URLQueryItem(name: "fmt", value: "json"),
                ]
            )
            return Self.parseMusicBrainzRelatedArtists(data)
        } catch {
            Log.library.debug("MusicBrainz related artists failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func musicBrainzTags(named name: String) async -> [String] {
        guard let mbid = await musicBrainzArtistID(named: name) else { return [] }
        do {
            let data = try await get(
                URL(string: "https://musicbrainz.org/ws/2/artist/\(mbid)")!,
                query: [
                    URLQueryItem(name: "inc", value: "tags"),
                    URLQueryItem(name: "fmt", value: "json"),
                ]
            )
            return Self.parseMusicBrainzTags(data)
        } catch {
            return []
        }
    }

    private func musicBrainzArtistID(named name: String) async -> String? {
        do {
            let data = try await get(
                URL(string: "https://musicbrainz.org/ws/2/artist")!,
                query: [
                    URLQueryItem(name: "query", value: "artist:\(name)"),
                    URLQueryItem(name: "limit", value: "1"),
                    URLQueryItem(name: "fmt", value: "json"),
                ]
            )
            return Self.parseMusicBrainzArtistID(data)
        } catch {
            return nil
        }
    }

    // MARK: - ListenBrainz

    private func listenBrainzSimilarArtists(named name: String) async -> [String]? {
        // Popularity / similarity endpoint — best-effort; ignore failures.
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        guard let url = URL(string: "\(Self.listenBrainzBase.absoluteString)/artist/\(encoded)/similar") else {
            return nil
        }
        do {
            let data = try await get(url, query: [
                URLQueryItem(name: "count", value: "8"),
            ])
            return Self.parseListenBrainzSimilar(data)
        } catch {
            // Fallback: collaborative recording similarity is artist-name based via search — skip if unavailable.
            Log.library.debug("ListenBrainz similar failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - HTTP

    private func get(_ base: URL, query: [URLQueryItem]) async throws -> Data {
        await throttle()
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        if !query.isEmpty {
            components.queryItems = (components.queryItems ?? []) + query
        }
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func throttle() async {
        let elapsed = Date().timeIntervalSince(lastRequestAt)
        if elapsed < Self.minInterval {
            let delay = Self.minInterval - elapsed
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        lastRequestAt = Date()
    }

    // MARK: - Parsing (testable)

    static func parseMusicBrainzArtistID(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let artists = root["artists"] as? [[String: Any]],
              let first = artists.first,
              let id = first["id"] as? String else {
            return nil
        }
        return id
    }

    static func parseMusicBrainzRelatedArtists(_ data: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let relations = root["relations"] as? [[String: Any]] else {
            return []
        }
        var names: [String] = []
        for rel in relations {
            let type = (rel["type"] as? String)?.lowercased() ?? ""
            guard type.contains("member") || type.contains("collaboration")
                    || type.contains("supporting") || type.contains("subgroup")
                    || type.contains("is person") || type == "tribute"
                    || type.contains("performer") || type.contains("vocal")
                    || type.contains("instrument") || type.contains("conductor")
                    || type.contains("remix") || type.contains("sibling")
                    || type.contains("parent") || type.contains("married")
                    || type.contains("involvement") || type.contains("artistic")
                    || type == "artist rename" || type.contains("founder")
                    || type.contains("related") || type.contains("voice")
                    || type.contains("is a") || !type.isEmpty else { continue }
            if let artist = rel["artist"] as? [String: Any],
               let name = artist["name"] as? String,
               !name.isEmpty {
                names.append(name)
            }
        }
        return names
    }

    static func parseMusicBrainzTags(_ data: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tags = root["tags"] as? [[String: Any]] else {
            return []
        }
        return tags
            .compactMap { tag -> (String, Int)? in
                guard let name = tag["name"] as? String, !name.isEmpty else { return nil }
                let count = tag["count"] as? Int ?? 0
                return (name, count)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    static func parseListenBrainzSimilar(_ data: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        // Payload shapes vary; accept a few common keys.
        let arrays: [[Any]] = [
            root["artists"] as? [Any],
            root["payload"] as? [Any],
            (root["payload"] as? [String: Any])?["artists"] as? [Any],
            root["similar_artists"] as? [Any],
        ].compactMap { $0 }

        var names: [String] = []
        for array in arrays {
            for item in array {
                if let s = item as? String {
                    names.append(s)
                } else if let dict = item as? [String: Any] {
                    if let n = dict["name"] as? String { names.append(n) }
                    else if let n = dict["artist_name"] as? String { names.append(n) }
                    else if let n = dict["artist"] as? String { names.append(n) }
                }
            }
        }
        return names
    }
}
