import Foundation

/// Free internet radio station — Radio Browser directory, curated seeds, or user URL.
/// No subscription. Not a DRM catalog.
struct RadioStation: Identifiable, Hashable, Codable, Sendable {
    var name: String
    var genre: String
    var streamURL: URL
    var isUserAdded: Bool
    var country: String?
    var countryCode: String?
    var tags: [String]
    var bitrate: Int?
    var stationUUID: String?
    var codec: String?

    var id: String {
        if let stationUUID, !stationUUID.isEmpty { return stationUUID }
        return streamURL.absoluteString
    }

    var tagsDisplay: String {
        let joined = tags.prefix(4).joined(separator: " · ")
        if !joined.isEmpty { return joined }
        return genre
    }

    var bitrateDisplay: String? {
        guard let bitrate, bitrate > 0 else { return nil }
        return "\(bitrate) kbps"
    }

    var countryDisplay: String? {
        if let country, !country.isEmpty { return country }
        if let countryCode, !countryCode.isEmpty {
            return Locale.current.localizedString(forRegionCode: countryCode) ?? countryCode
        }
        return nil
    }

    init(
        name: String,
        genre: String,
        streamURL: URL,
        isUserAdded: Bool,
        country: String? = nil,
        countryCode: String? = nil,
        tags: [String] = [],
        bitrate: Int? = nil,
        stationUUID: String? = nil,
        codec: String? = nil
    ) {
        self.name = name
        self.genre = genre
        self.streamURL = streamURL
        self.isUserAdded = isUserAdded
        self.country = country
        self.countryCode = countryCode
        self.tags = tags.isEmpty && !genre.isEmpty && genre != "Custom" && genre != "Radio"
            ? [genre]
            : tags
        self.bitrate = bitrate
        self.stationUUID = stationUUID
        self.codec = codec
    }

    enum CodingKeys: String, CodingKey {
        case name, genre, streamURL, isUserAdded
        case country, countryCode, tags, bitrate, stationUUID, codec
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        genre = try c.decode(String.self, forKey: .genre)
        streamURL = try c.decode(URL.self, forKey: .streamURL)
        isUserAdded = try c.decodeIfPresent(Bool.self, forKey: .isUserAdded) ?? true
        country = try c.decodeIfPresent(String.self, forKey: .country)
        countryCode = try c.decodeIfPresent(String.self, forKey: .countryCode)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        bitrate = try c.decodeIfPresent(Int.self, forKey: .bitrate)
        stationUUID = try c.decodeIfPresent(String.self, forKey: .stationUUID)
        codec = try c.decodeIfPresent(String.self, forKey: .codec)
    }
}

enum RadioCatalog {
    private static let userKey = "userRadioStations"
    private static let favoritesKey = "radioBrowserFavorites"

    /// Small curated list of well-known free/open streams (SomaFM / public Icecast).
    /// Kept as Favorites seeds when the user has no saved stations yet.
    static let curated: [RadioStation] = [
        RadioStation(
            name: "SomaFM Groove Salad",
            genre: "Ambient / Downtempo",
            streamURL: URL(string: "https://ice1.somafm.com/groovesalad-128-mp3")!,
            isUserAdded: false,
            country: "United States of America",
            countryCode: "US",
            tags: ["ambient", "downtempo"],
            bitrate: 128
        ),
        RadioStation(
            name: "SomaFM Drone Zone",
            genre: "Ambient",
            streamURL: URL(string: "https://ice1.somafm.com/dronezone-128-mp3")!,
            isUserAdded: false,
            country: "United States of America",
            countryCode: "US",
            tags: ["ambient"],
            bitrate: 128
        ),
        RadioStation(
            name: "SomaFM Indie Pop Rocks",
            genre: "Indie",
            streamURL: URL(string: "https://ice1.somafm.com/indiepop-128-mp3")!,
            isUserAdded: false,
            country: "United States of America",
            countryCode: "US",
            tags: ["indie", "pop"],
            bitrate: 128
        ),
    ]

    static func loadUserStations() -> [RadioStation] {
        decodeStations(forKey: userKey)
    }

    static func saveUserStations(_ stations: [RadioStation]) {
        encodeStations(stations, forKey: userKey)
    }

    static func loadFavorites() -> [RadioStation] {
        decodeStations(forKey: favoritesKey)
    }

    static func saveFavorites(_ stations: [RadioStation]) {
        encodeStations(stations, forKey: favoritesKey)
    }

    static func isFavorite(_ station: RadioStation) -> Bool {
        loadFavorites().contains { $0.id == station.id }
            || loadUserStations().contains { $0.id == station.id }
    }

    static func toggleFavorite(_ station: RadioStation) {
        var favs = loadFavorites()
        if let idx = favs.firstIndex(where: { $0.id == station.id }) {
            favs.remove(at: idx)
        } else {
            favs.insert(station, at: 0)
        }
        saveFavorites(favs)
    }

    static func addUserStation(_ station: RadioStation) {
        var user = loadUserStations()
        guard !user.contains(where: { $0.streamURL == station.streamURL }) else { return }
        user.append(station)
        saveUserStations(user)
    }

    static func removeUserStation(id: String) {
        var user = loadUserStations()
        user.removeAll { $0.id == id }
        saveUserStations(user)
        var favs = loadFavorites()
        favs.removeAll { $0.id == id }
        saveFavorites(favs)
    }

    /// Favorites tab: Radio Browser favorites + custom URLs; curated seeds when empty.
    static func favoriteStations() -> [RadioStation] {
        let favorites = loadFavorites()
        let custom = loadUserStations()
        var seen = Set<String>()
        var result: [RadioStation] = []
        for station in favorites + custom {
            if seen.insert(station.id).inserted {
                result.append(station)
            }
        }
        return result.isEmpty ? curated : result
    }

    /// Back-compat helper used by older call sites.
    static func allStations() -> [RadioStation] {
        favoriteStations()
    }

    private static func decodeStations(forKey key: String) -> [RadioStation] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([RadioStation].self, from: data)
        else { return [] }
        return decoded
    }

    private static func encodeStations(_ stations: [RadioStation], forKey key: String) {
        if let data = try? JSONEncoder().encode(stations) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
