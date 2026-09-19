import Foundation

/// Materialize cloud-provider files (iCloud Drive, Google Drive via Files, …)
/// before AVPlayer opens them. Prefer download-to-play when the provider
/// exposes placeholders / ubiquitous items.
enum CloudFileAccess {

    static func prepareForPlayback(at url: URL) async {
        await startUbiquitousDownloadIfNeeded(at: url)
        await coordinateRead(at: url)
    }

    private static func startUbiquitousDownloadIfNeeded(at url: URL) async {
        let values = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
        ])
        guard values?.isUbiquitousItem == true else { return }

        if values?.ubiquitousItemDownloadingStatus == .current { return }

        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            Log.player.info("Started iCloud download: \(url.lastPathComponent)")
        } catch {
            Log.player.warning("iCloud download start failed: \(error.localizedDescription)")
            return
        }

        for _ in 0..<40 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            let refreshed = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if refreshed?.ubiquitousItemDownloadingStatus == .current { return }
            if Task.isCancelled { return }
        }
        Log.player.warning("Timed out waiting for iCloud download: \(url.lastPathComponent)")
    }

    private static func coordinateRead(at url: URL) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            var didResume = false
            var coordinatorError: NSError?
            let coordinator = NSFileCoordinator()
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { coordinatedURL in
                if let handle = try? FileHandle(forReadingFrom: coordinatedURL) {
                    _ = try? handle.read(upToCount: 1)
                    try? handle.close()
                }
                didResume = true
                cont.resume()
            }
            if !didResume {
                if let coordinatorError {
                    Log.player.debug("File coordinate failed: \(coordinatorError.localizedDescription)")
                }
                cont.resume()
            }
        }
    }
}
