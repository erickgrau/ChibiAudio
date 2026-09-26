import Foundation
import Testing
@testable import LocalMusic

@MainActor struct RadioBrowserClientTests {

    @Test func decodeStationsPrefersResolvedURLAndUUID() throws {
        let json = """
        [
          {
            "stationuuid": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            "name": "Test Jazz",
            "url": "http://example.com/raw",
            "url_resolved": "https://example.com/resolved.mp3",
            "tags": "jazz,cool",
            "country": "Germany",
            "countrycode": "DE",
            "bitrate": 192,
            "codec": "MP3"
          },
          {
            "stationuuid": "ffffffff-0000-1111-2222-333333333333",
            "name": "Broken",
            "url": "not-a-url",
            "url_resolved": "",
            "tags": "",
            "countrycode": "US",
            "bitrate": 0
          }
        ]
        """.data(using: .utf8)!

        let stations = try RadioBrowserClient.decodeStations(json)
        #expect(stations.count == 1)
        let station = stations[0]
        #expect(station.name == "Test Jazz")
        #expect(station.streamURL.absoluteString == "https://example.com/resolved.mp3")
        #expect(station.stationUUID == "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        #expect(station.countryCode == "DE")
        #expect(station.bitrate == 192)
        #expect(station.tags == ["jazz", "cool"])
        #expect(station.id == "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        #expect(station.bitrateDisplay == "192 kbps")
    }

    @Test func radioStationCodableRoundTripPreservesLegacyFields() throws {
        let legacy = """
        [{"name":"My Stream","genre":"Custom","streamURL":"https://ice.example/x","isUserAdded":true}]
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode([RadioStation].self, from: legacy)
        #expect(decoded.count == 1)
        #expect(decoded[0].name == "My Stream")
        #expect(decoded[0].tags.isEmpty || decoded[0].genre == "Custom")
        #expect(decoded[0].stationUUID == nil)

        let data = try JSONEncoder().encode(decoded)
        let again = try JSONDecoder().decode([RadioStation].self, from: data)
        #expect(again[0].streamURL.absoluteString == "https://ice.example/x")
    }

    @Test func favoriteToggleUsesStationIdentity() {
        let key = "radioBrowserFavorites"
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let station = RadioStation(
            name: "Fav",
            genre: "Pop",
            streamURL: URL(string: "https://example.com/fav")!,
            isUserAdded: false,
            stationUUID: "uuid-fav-1"
        )
        #expect(RadioCatalog.isFavorite(station) == false)
        RadioCatalog.toggleFavorite(station)
        #expect(RadioCatalog.isFavorite(station) == true)
        #expect(RadioCatalog.loadFavorites().count == 1)
        RadioCatalog.toggleFavorite(station)
        #expect(RadioCatalog.isFavorite(station) == false)
    }
}
