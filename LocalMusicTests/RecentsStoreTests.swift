import Foundation
import Testing
@testable import LocalMusic

@MainActor
@Suite
struct RecentsStoreTests {

    private func makeStore(maxCount: Int = 40) throws -> (RecentsStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecentsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = RecentsStore(documentsURL: dir, maxCount: maxCount)
        return (store, dir)
    }

    @Test func record_prependsAndDedupes() throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let a = Fixtures.track(title: "A", path: "/r/a.mp3")
        let b = Fixtures.track(title: "B", path: "/r/b.mp3")

        store.record(a)
        store.record(b)
        #expect(store.entries.map(\.title) == ["B", "A"])

        store.record(a)
        #expect(store.entries.map(\.title) == ["A", "B"])
        #expect(store.entries.count == 2)
    }

    @Test func record_trimsToMaxCount() throws {
        let (store, dir) = try makeStore(maxCount: 3)
        defer { try? FileManager.default.removeItem(at: dir) }

        for i in 0..<5 {
            store.record(Fixtures.track(title: "T\(i)", path: "/r/t\(i).mp3"))
        }
        #expect(store.entries.count == 3)
        #expect(store.entries.map(\.title) == ["T4", "T3", "T2"])
    }

    @Test func persistsAcrossReload() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecentsPersist-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let first = RecentsStore(documentsURL: dir, maxCount: 10)
        first.record(Fixtures.track(title: "Persist", path: "/r/persist.mp3"))

        let second = RecentsStore(documentsURL: dir, maxCount: 10)
        #expect(second.entries.count == 1)
        #expect(second.entries.first?.title == "Persist")
    }

    @Test func clear_emptiesEntries() throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        store.record(Fixtures.track(title: "X", path: "/r/x.mp3"))
        store.clear()
        #expect(store.entries.isEmpty)
    }
}
