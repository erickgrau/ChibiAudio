import Foundation
import Testing
@testable import LocalMusic

@Suite("Bandcamp Subsonic JSON")
struct BandcampSubsonicClientTests {

    @Test func statusOK_parsesOkResponse() throws {
        let json = """
        {"subsonic-response":{"status":"ok","version":"1.16.0"}}
        """
        #expect(try BandcampSubsonicClient.statusOK(Data(json.utf8)) == true)
    }

    @Test func statusOK_rejectsFailedResponse() throws {
        let json = """
        {"subsonic-response":{"status":"failed","error":{"code":40,"message":"Wrong username or password"}}}
        """
        #expect(try BandcampSubsonicClient.statusOK(Data(json.utf8)) == false)
        #expect(try BandcampSubsonicClient.errorMessage(Data(json.utf8)) == "Wrong username or password")
    }

    @Test func parseAlbumList2_readsAlbums() throws {
        let json = """
        {"subsonic-response":{"status":"ok","albumList2":{"album":[
          {"id":"a1","name":"Album One","artist":"Artist A","songCount":8},
          {"id":"a2","title":"Album Two","artist":"Artist B","coverArt":"c2"}
        ]}}}
        """
        let albums = try BandcampSubsonicClient.parseAlbumList2(Data(json.utf8))
        #expect(albums.count == 2)
        #expect(albums[0].id == "a1")
        #expect(albums[0].name == "Album One")
        #expect(albums[0].artist == "Artist A")
        #expect(albums[0].songCount == 8)
        #expect(albums[1].name == "Album Two")
        #expect(albums[1].coverArtID == "c2")
    }

    @Test func parseAlbumSongs_readsTracks() throws {
        let json = """
        {"subsonic-response":{"status":"ok","album":{"name":"LP","song":[
          {"id":"t1","title":"Track 1","artist":"A","album":"LP","duration":180},
          {"id":"t2","title":"Track 2","artist":"A","duration":"90"}
        ]}}}
        """
        let tracks = try BandcampSubsonicClient.parseAlbumSongs(Data(json.utf8))
        #expect(tracks.count == 2)
        #expect(tracks[0].id == "t1")
        #expect(tracks[0].durationSeconds == 180)
        #expect(tracks[1].durationSeconds == 90)
        #expect(tracks[1].album == "LP")
    }

    @Test func defaultServerURL_isBandcampSubsonic() {
        #expect(BandcampSubsonicClient.defaultServerURL == "https://bandcamp.com/api/subsonic")
    }
}

@Suite("AdMob config")
struct AdMobConfigTests {

    @Test func shouldShowBanner_requiresConfigAndNoPlus() {
        // Without GADApplicationIdentifier / env, isConfigured is false in unit tests.
        #expect(AdMobConfig.shouldShowBanner(isPlusActive: false) == AdMobConfig.isConfigured)
        #expect(AdMobConfig.shouldShowBanner(isPlusActive: true) == false)
    }
}

@Suite("Plus product ID")
struct PlusStoreIDTests {

    @Test func productID_matchesStoreKit() {
        #expect(PlusStore.productID == "com.chibitek.ChibiAudio.plus.monthly")
        #expect(PlusStore.productID == AppBranding.plusMonthlyProductID)
    }
}

@Suite("App branding lock")
struct AppBrandingTests {

    @Test func lockedNames() {
        #expect(AppBranding.displayName == "ChibiAudio")
        #expect(AppBranding.appStoreSubtitle == "Offline HiFi Player")
        #expect(AppBranding.bundleIdentifier == "com.chibitek.ChibiAudio")
        #expect(AppBranding.tagline == "ChibiAudio — Offline HiFi Player")
        #expect(!AppBranding.tagline.localizedCaseInsensitiveContains("Soft PASS"))
    }

    @Test func infoPlistDocumentsSubtitle() {
        let subtitle = Bundle.main.object(forInfoDictionaryKey: "ChibiAudioAppStoreSubtitle") as? String
        // Test host may not merge the app Info.plist; when present it must match.
        if let subtitle {
            #expect(subtitle == "Offline HiFi Player")
        }
        let display = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        if let display {
            #expect(display == "ChibiAudio")
        }
    }
}

@Suite("CarPlay and Watch stubs")
struct CompanionStubTests {

    @Test func carPlay_requiresPlus_appleAudioTemplatesOnly() {
        #expect(CarPlayAudioTemplateStub.requiresPlus)
        #expect(CarPlayAudioTemplateStub.usesAppleAudioTemplatesOnly)
        #expect(CarPlayAudioTemplateStub.customDashCanvas == false)
        #expect(CarPlayAudioTemplateStub.visualizersOnCarPlay == false)
        #expect(CarPlayAudioTemplateStub.supportsBrowseTemplate)
        #expect(CarPlayAudioTemplateStub.supportsQueueTemplate)
        #expect(CarPlayAudioTemplateStub.maximizeNowPlayingArtwork)
        #expect(CarPlayAudioTemplateStub.isUnlocked(isPlusActive: false) == false)
        #expect(CarPlayAudioTemplateStub.isUnlocked(isPlusActive: true) == true)
        #expect(!CarPlayAudioTemplateStub.featureDetail.localizedCaseInsensitiveContains("Soft PASS"))
        #expect(!CarPlayAudioTemplateStub.featureDetail.localizedCaseInsensitiveContains("Soft FAIL"))
    }

    @Test func watch_requiresPlus() {
        #expect(WatchCompanionStub.requiresPlus)
        #expect(WatchCompanionStub.isUnlocked(isPlusActive: false) == false)
        #expect(WatchCompanionStub.isUnlocked(isPlusActive: true) == true)
    }
}
