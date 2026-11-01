import SwiftUI

/// Soft PASS tab IDs — Home is the default landing. The iOS tab bar shows
/// the first five; the Mac sidebar also lists the Albums/Artists browsers
/// and the Plex and Bandcamp sources, which iOS reaches from Home/Settings.
enum ChibiTab: Int, Hashable, Sendable {
    case home = 0
    case library = 1
    case nowPlaying = 2
    case playlists = 3
    case radio = 4
    case albums = 5
    case artists = 6
    case plex = 7
    case bandcamp = 8
}

/// Shared tab selection so Home shortcuts can jump without a Sendable closure env key.
@Observable
@MainActor
final class TabRouter {
    var selected: ChibiTab = .home
    /// Mac only: the Up Next inspector beside whatever section is showing.
    var showsQueue = false
}
