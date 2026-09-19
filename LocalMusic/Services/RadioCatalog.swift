import Foundation

/// Free internet radio: curated Icecast/Shoutcast-style streams + user URLs.
/// No subscription. Not a DRM catalog.
struct RadioStation: Identifiable, Hashable, Codable, Sendable {
    var id: String { streamURL.absoluteString }
    var name: String
    var genre: String
    var streamURL: URL
    var isUserAdded: Bool
}

enum RadioCatalog {
    private static let userKey = "userRadioStations"

    /// Small curated list of well-known free/open streams (SomaFM / public Icecast).
    /// URLs may change; users can paste their own.
    static let curated: [RadioStation] = [
        RadioStation(
            name: "SomaFM Groove Salad",
            genre: "Ambient / Downtempo",
            streamURL: URL(string: "https://ice1.somafm.com/groovesalad-128-mp3")!,
            isUserAdded: false
        ),
        RadioStation(
            name: "SomaFM Drone Zone",
            genre: "Ambient",
            streamURL: URL(string: "https://ice1.somafm.com/dronezone-128-mp3")!,
            isUserAdded: false
        ),
        RadioStation(
            name: "SomaFM Indie Pop Rocks",
            genre: "Indie",
            streamURL: URL(string: "https://ice1.somafm.com/indiepop-128-mp3")!,
            isUserAdded: false
        ),
    ]

    static func loadUserStations() -> [RadioStation] {
        guard let data = UserDefaults.standard.data(forKey: userKey),
              let decoded = try? JSONDecoder().decode([RadioStation].self, from: data)
        else { return [] }
        return decoded
    }

    static func saveUserStations(_ stations: [RadioStation]) {
        if let data = try? JSONEncoder().encode(stations) {
            UserDefaults.standard.set(data, forKey: userKey)
        }
    }

    static func allStations() -> [RadioStation] {
        curated + loadUserStations()
    }
}
