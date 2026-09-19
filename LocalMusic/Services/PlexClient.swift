import Foundation

/// Minimal Plex Media Server client for personal (free) music libraries.
///
/// Uses X-Plex-Token auth. LAN direct play preferred; transcode only as fallback
/// (labeled). Plex Pass is **not** required for basic local streaming of *your*
/// library — remote / some Plexamp features may need Pass (documented in README).
@Observable
@MainActor
final class PlexClient {

    static let shared = PlexClient()

    private static let serverURLKey = "plexServerURL"
    private static let tokenKey = "plexToken"

    var serverURLString: String {
        didSet { UserDefaults.standard.set(serverURLString, forKey: Self.serverURLKey) }
    }

    var token: String {
        didSet { UserDefaults.standard.set(token, forKey: Self.tokenKey) }
    }

    var lastError: String?
    var musicSections: [PlexDirectory] = []
    var isConfigured: Bool {
        !serverURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private init() {
        serverURLString = UserDefaults.standard.string(forKey: Self.serverURLKey) ?? ""
        token = UserDefaults.standard.string(forKey: Self.tokenKey) ?? ""
    }

    struct PlexDirectory: Identifiable, Hashable, Sendable {
        var id: String { key }
        var key: String
        var title: String
        var type: String
    }

    struct PlexTrack: Identifiable, Hashable, Sendable {
        var id: String { ratingKey }
        var ratingKey: String
        var title: String
        var artist: String
        var album: String
        var durationMs: Double
        var mediaPartKey: String?
    }

    func directPlayURL(serverURL: String, ratingKey: String) -> URL? {
        let base = serverURLString.isEmpty ? serverURL : serverURLString
        guard isConfigured || !base.isEmpty, !token.isEmpty else { return nil }
        // /library/metadata/{ratingKey}/[file] — use the transcoder-free media path
        // when possible. `download=1` asks for original when PMS allows.
        var components = URLComponents(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        guard components != nil else { return nil }
        let path = "/library/metadata/\(ratingKey)/download"
        // Prefer the stream endpoint that serves the original part:
        //   {server}/library/metadata/{id}/[file]?X-Plex-Token=
        // Using /file via metadata children is more accurate; for MVP use stream:
        let stream = "\(base.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/library/metadata/\(ratingKey)/stream?download=0&X-Plex-Token=\(token)"
        _ = path
        return URL(string: stream)
    }

    func refreshMusicLibraries() async {
        guard isConfigured else {
            lastError = "Set server URL and X-Plex-Token in Settings"
            return
        }
        lastError = nil
        do {
            let url = try endpoint("/library/sections")
            let (data, _) = try await URLSession.shared.data(from: url)
            let all = try Self.parseDirectories(data)
            // Plex music libraries typically report type "artist".
            let music = all.filter { $0.type == "artist" }
            musicSections = music.isEmpty ? all : music
        } catch {
            lastError = error.localizedDescription
            Log.library.error("Plex sections failed: \(error.localizedDescription)")
        }
    }

    func fetchTracks(sectionKey: String) async -> [PlexTrack] {
        guard isConfigured else { return [] }
        do {
            let url = try endpoint("/library/sections/\(sectionKey)/all", query: [
                URLQueryItem(name: "type", value: "10"), // track
            ])
            let (data, _) = try await URLSession.shared.data(from: url)
            return try Self.parseTracks(data)
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    private func endpoint(_ path: String, query: [URLQueryItem] = []) throws -> URL {
        let trimmed = serverURLString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(string: trimmed + path) else {
            throw URLError(.badURL)
        }
        var items = query
        items.append(URLQueryItem(name: "X-Plex-Token", value: token))
        components.queryItems = items
        guard let url = components.url else { throw URLError(.badURL) }
        return url
    }

    // Plex default XML — lightweight string scrape to avoid adding a dependency.
    private static func parseDirectories(_ data: Data) throws -> [PlexDirectory] {
        guard let xml = String(data: data, encoding: .utf8) else { return [] }
        var results: [PlexDirectory] = []
        let pattern = #"Directory[^>]*key="([^"]+)"[^>]*title="([^"]+)"[^>]*type="([^"]+)""#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(xml.startIndex..., in: xml)
        for match in regex.matches(in: xml, range: range) {
            guard let keyR = Range(match.range(at: 1), in: xml),
                  let titleR = Range(match.range(at: 2), in: xml),
                  let typeR = Range(match.range(at: 3), in: xml) else { continue }
            results.append(PlexDirectory(
                key: String(xml[keyR]),
                title: String(xml[titleR]).removingHTMLEntities,
                type: String(xml[typeR])
            ))
        }
        // Attribute order may vary — second pass for type-before-title layouts.
        if results.isEmpty {
            let alt = #"Directory[^>]*title="([^"]+)"[^>]*key="([^"]+)"[^>]*type="([^"]+)""#
            let altRegex = try NSRegularExpression(pattern: alt)
            for match in altRegex.matches(in: xml, range: range) {
                guard let titleR = Range(match.range(at: 1), in: xml),
                      let keyR = Range(match.range(at: 2), in: xml),
                      let typeR = Range(match.range(at: 3), in: xml) else { continue }
                results.append(PlexDirectory(
                    key: String(xml[keyR]),
                    title: String(xml[titleR]).removingHTMLEntities,
                    type: String(xml[typeR])
                ))
            }
        }
        return results
    }

    private static func parseTracks(_ data: Data) throws -> [PlexTrack] {
        guard let xml = String(data: data, encoding: .utf8) else { return [] }
        var results: [PlexTrack] = []
        // Track elements are <Track ... ratingKey= title= grandparentTitle= parentTitle= duration=
        let pattern = #"<Track\b([^>]+)>"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(xml.startIndex..., in: xml)
        for match in regex.matches(in: xml, range: range) {
            guard let attrR = Range(match.range(at: 1), in: xml) else { continue }
            let attrs = String(xml[attrR])
            guard let ratingKey = attr(attrs, "ratingKey") ?? attr(attrs, "key"),
                  let title = attr(attrs, "title") else { continue }
            let artist = attr(attrs, "grandparentTitle") ?? attr(attrs, "originalTitle") ?? "Unknown Artist"
            let album = attr(attrs, "parentTitle") ?? "Unknown Album"
            let durationMs = Double(attr(attrs, "duration") ?? "0") ?? 0
            results.append(PlexTrack(
                ratingKey: ratingKey,
                title: title.removingHTMLEntities,
                artist: artist.removingHTMLEntities,
                album: album.removingHTMLEntities,
                durationMs: durationMs,
                mediaPartKey: nil
            ))
        }
        return results
    }

    private static func attr(_ attrs: String, _ name: String) -> String? {
        let pattern = #"\#(name)="([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: attrs, range: NSRange(attrs.startIndex..., in: attrs)),
              let r = Range(match.range(at: 1), in: attrs) else { return nil }
        return String(attrs[r])
    }
}

private extension String {
    var removingHTMLEntities: String {
        replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}
