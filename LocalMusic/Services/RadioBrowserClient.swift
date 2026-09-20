import Darwin
import Foundation

/// Community [Radio Browser](https://api.radio-browser.info) client.
///
/// Etiquette:
/// - Discover a working mirror (DNS / `/json/servers`), never hard-pin forever
/// - Send a speaking `User-Agent` (`ChibiAudio/…`)
/// - Prefer `stationuuid` + `url_resolved`; report play clicks lightly
/// - Cache lists briefly so we don’t hammer mirrors
@Observable
@MainActor
final class RadioBrowserClient {

    static let shared = RadioBrowserClient()

    private static let userAgent = "ChibiAudio/1.0"
    private static let seedHosts = [
        "de1.api.radio-browser.info",
        "de2.api.radio-browser.info",
    ]
    private static let discoveryHost = "all.api.radio-browser.info"
    private static let cacheTTL: TimeInterval = 15 * 60
    private static let defaultLimit = 80

    private(set) var baseHost: String?
    private(set) var lastError: String?
    private(set) var isOffline = false
    private(set) var isLoading = false

    private var countriesCache: (date: Date, value: [RadioCountry])?
    private var tagsCache: (date: Date, value: [RadioTag])?
    private var stationCaches: [String: (date: Date, value: [RadioStation])] = [:]
    private var resolveTask: Task<String, Error>?

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 40
        config.httpAdditionalHeaders = [
            "User-Agent": RadioBrowserClient.userAgent,
            "Accept": "application/json",
        ]
        return URLSession(configuration: config)
    }()

    private init() {}

    // MARK: - Public API

    func countries(forceRefresh: Bool = false) async -> [RadioCountry] {
        if !forceRefresh,
           let cache = countriesCache,
           Date().timeIntervalSince(cache.date) < Self.cacheTTL {
            return cache.value
        }
        do {
            let data = try await getJSON(
                path: "/json/countrycodes",
                query: [
                    URLQueryItem(name: "order", value: "stationcount"),
                    URLQueryItem(name: "reverse", value: "true"),
                    URLQueryItem(name: "limit", value: "250"),
                ]
            )
            let decoded = try JSONDecoder().decode([APICountry].self, from: data)
            let mapped = decoded
                .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map { RadioCountry(code: $0.name.uppercased(), stationCount: $0.stationcount) }
            countriesCache = (Date(), mapped)
            clearError()
            return mapped
        } catch {
            recordFailure(error)
            return countriesCache?.value ?? []
        }
    }

    func tags(forceRefresh: Bool = false) async -> [RadioTag] {
        if !forceRefresh,
           let cache = tagsCache,
           Date().timeIntervalSince(cache.date) < Self.cacheTTL {
            return cache.value
        }
        do {
            let data = try await getJSON(
                path: "/json/tags",
                query: [
                    URLQueryItem(name: "order", value: "stationcount"),
                    URLQueryItem(name: "reverse", value: "true"),
                    URLQueryItem(name: "limit", value: "200"),
                ]
            )
            let decoded = try JSONDecoder().decode([APITag].self, from: data)
            let mapped = decoded
                .map { RadioTag(name: $0.name, stationCount: $0.stationcount) }
                .filter { !$0.name.isEmpty && $0.stationCount > 0 }
            tagsCache = (Date(), mapped)
            clearError()
            return mapped
        } catch {
            recordFailure(error)
            return tagsCache?.value ?? []
        }
    }

    func stationsByCountryCode(_ code: String, forceRefresh: Bool = false) async -> [RadioStation] {
        let key = "cc:\(code.uppercased())"
        return await stations(
            cacheKey: key,
            path: "/json/stations/bycountrycodeexact/\(code.uppercased())",
            forceRefresh: forceRefresh
        )
    }

    func stationsByTag(_ tag: String, forceRefresh: Bool = false) async -> [RadioStation] {
        let encoded = tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tag
        let key = "tag:\(tag.lowercased())"
        return await stations(
            cacheKey: key,
            path: "/json/stations/bytagexact/\(encoded)",
            forceRefresh: forceRefresh
        )
    }

    func searchStations(name: String, forceRefresh: Bool = false) async -> [RadioStation] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        let key = "search:\(trimmed.lowercased())"
        if !forceRefresh,
           let cache = stationCaches[key],
           Date().timeIntervalSince(cache.date) < Self.cacheTTL {
            return cache.value
        }
        do {
            let data = try await getJSON(
                path: "/json/stations/search",
                query: [
                    URLQueryItem(name: "name", value: trimmed),
                    URLQueryItem(name: "hidebroken", value: "true"),
                    URLQueryItem(name: "order", value: "clickcount"),
                    URLQueryItem(name: "reverse", value: "true"),
                    URLQueryItem(name: "limit", value: String(Self.defaultLimit)),
                ]
            )
            let mapped = try Self.decodeStations(data)
            stationCaches[key] = (Date(), mapped)
            clearError()
            return mapped
        } catch {
            recordFailure(error)
            return stationCaches[key]?.value ?? []
        }
    }

    /// Soft PASS etiquette: record a play so broken stations get flagged.
    func reportClick(stationUUID: String) {
        let uuid = stationUUID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uuid.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.getJSON(path: "/json/url/\(uuid)", query: [], affectsLoading: false)
            } catch {
                Log.library.debug("Radio Browser click report skipped: \(error.localizedDescription)")
            }
        }
    }

    func refreshConnectivity() async {
        do {
            _ = try await resolveWorkingHost(force: true)
            clearError()
        } catch {
            recordFailure(error)
        }
    }

    // MARK: - Internals

    private func stations(cacheKey: String, path: String, forceRefresh: Bool) async -> [RadioStation] {
        if !forceRefresh,
           let cache = stationCaches[cacheKey],
           Date().timeIntervalSince(cache.date) < Self.cacheTTL {
            return cache.value
        }
        do {
            let data = try await getJSON(
                path: path,
                query: [
                    URLQueryItem(name: "hidebroken", value: "true"),
                    URLQueryItem(name: "order", value: "clickcount"),
                    URLQueryItem(name: "reverse", value: "true"),
                    URLQueryItem(name: "limit", value: String(Self.defaultLimit)),
                ]
            )
            let mapped = try Self.decodeStations(data)
            stationCaches[cacheKey] = (Date(), mapped)
            clearError()
            return mapped
        } catch {
            recordFailure(error)
            return stationCaches[cacheKey]?.value ?? []
        }
    }

    private func getJSON(path: String, query: [URLQueryItem], affectsLoading: Bool = true) async throws -> Data {
        if affectsLoading { isLoading = true }
        defer { if affectsLoading { isLoading = false } }
        let host = try await resolveWorkingHost(force: false)
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw RadioBrowserError.badURL
        }
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RadioBrowserError.badResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw RadioBrowserError.httpStatus(http.statusCode)
        }
        return data
    }

    private func resolveWorkingHost(force: Bool) async throws -> String {
        if !force, let baseHost {
            return baseHost
        }
        if let resolveTask {
            return try await resolveTask.value
        }
        let task = Task { () throws -> String in
            defer { self.resolveTask = nil }
            var candidates = Self.seedHosts
            let discovered = await Self.discoverHosts()
            for host in discovered where !candidates.contains(host) {
                candidates.insert(host, at: 0)
            }
            var lastError: Error = RadioBrowserError.noServers
            for host in candidates {
                do {
                    try await self.ping(host: host)
                    self.baseHost = host
                    Log.library.info("Radio Browser mirror: \(host)")
                    return host
                } catch {
                    lastError = error
                }
            }
            throw lastError
        }
        resolveTask = task
        return try await task.value
    }

    private func ping(host: String) async throws {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/json/stats"
        guard let url = components.url else { throw RadioBrowserError.badURL }
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RadioBrowserError.badResponse
        }
    }

    /// Prefer DNS for `all.api.radio-browser.info`, then `/json/servers` on a seed.
    private static func discoverHosts() async -> [String] {
        var hosts: [String] = []
        hosts.append(contentsOf: await dnsHosts(for: discoveryHost))
        if let fromAPI = await serversList(from: seedHosts.first ?? discoveryHost) {
            for host in fromAPI where !hosts.contains(host) {
                hosts.append(host)
            }
        }
        return hosts
    }

    private static func dnsHosts(for name: String) async -> [String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var hints = addrinfo(
                    ai_flags: AI_ADDRCONFIG,
                    ai_family: AF_UNSPEC,
                    ai_socktype: SOCK_STREAM,
                    ai_protocol: IPPROTO_TCP,
                    ai_addrlen: 0,
                    ai_canonname: nil,
                    ai_addr: nil,
                    ai_next: nil
                )
                var result: UnsafeMutablePointer<addrinfo>?
                let status = getaddrinfo(name, "443", &hints, &result)
                defer { if let result { freeaddrinfo(result) } }
                guard status == 0, let first = result else {
                    continuation.resume(returning: [])
                    return
                }
                var seen = Set<String>()
                var pointer: UnsafeMutablePointer<addrinfo>? = first
                while let info = pointer {
                    var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(
                        info.pointee.ai_addr,
                        socklen_t(info.pointee.ai_addrlen),
                        &hostBuffer,
                        socklen_t(hostBuffer.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    ) == 0 {
                        let ip = String(cString: hostBuffer)
                        // Reverse look up hostnames when possible; keep numeric as last resort seed.
                        if let reverse = reverseDNS(ip: ip), reverse.contains("radio-browser") {
                            seen.insert(reverse)
                        }
                    }
                    pointer = info.pointee.ai_next
                }
                // Round-robin name itself is a valid HTTPS host.
                seen.insert(name)
                continuation.resume(returning: Array(seen))
            }
        }
    }

    private static func reverseDNS(ip: String) -> String? {
        var hints = addrinfo(
            ai_flags: AI_NUMERICHOST,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(ip, nil, &hints, &result) == 0, let info = result else { return nil }
        defer { freeaddrinfo(info) }
        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(
            info.pointee.ai_addr,
            socklen_t(info.pointee.ai_addrlen),
            &hostBuffer,
            socklen_t(hostBuffer.count),
            nil,
            0,
            NI_NAMEREQD
        ) == 0 else { return nil }
        return String(cString: hostBuffer)
    }

    private static func serversList(from host: String) async -> [String]? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/json/servers"
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode([APIServer].self, from: data)
            return decoded.map(\.name).filter { !$0.isEmpty }
        } catch {
            return nil
        }
    }

    static func decodeStations(_ data: Data) throws -> [RadioStation] {
        let decoded = try JSONDecoder().decode([APIStation].self, from: data)
        return decoded.compactMap { api in
            let raw = api.url_resolved?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? api.url_resolved!
                : (api.url ?? "")
            guard let url = URL(string: raw),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https"
            else { return nil }
            let tags = (api.tags ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let name = api.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let name, !name.isEmpty else { return nil }
            return RadioStation(
                name: name,
                genre: tags.first.map { $0.capitalized } ?? "Radio",
                streamURL: url,
                isUserAdded: false,
                country: api.country,
                countryCode: api.countrycode?.uppercased(),
                tags: tags,
                bitrate: api.bitrate.flatMap { $0 > 0 ? $0 : nil },
                stationUUID: api.stationuuid,
                codec: api.codec
            )
        }
    }

    private func clearError() {
        lastError = nil
        isOffline = false
    }

    private func recordFailure(_ error: Error) {
        lastError = error.localizedDescription
        isOffline = true
        Log.library.error("Radio Browser: \(error.localizedDescription)")
    }
}

// MARK: - Public list models

struct RadioCountry: Identifiable, Hashable, Sendable {
    var id: String { code }
    var code: String
    var stationCount: Int

    var displayName: String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }
}

struct RadioTag: Identifiable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var stationCount: Int
}

enum RadioBrowserError: LocalizedError {
    case badURL
    case badResponse
    case httpStatus(Int)
    case noServers

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid Radio Browser URL"
        case .badResponse: return "Radio Browser returned an unexpected response"
        case .httpStatus(let code): return "Radio Browser HTTP \(code)"
        case .noServers: return "No Radio Browser mirrors reachable"
        }
    }
}

// MARK: - API DTOs

private struct APICountry: Decodable {
    var name: String
    var stationcount: Int
}

private struct APITag: Decodable {
    var name: String
    var stationcount: Int
}

private struct APIServer: Decodable {
    var name: String
}

private struct APIStation: Decodable {
    var stationuuid: String?
    var name: String?
    var url: String?
    var url_resolved: String?
    var tags: String?
    var country: String?
    var countrycode: String?
    var bitrate: Int?
    var codec: String?
}
