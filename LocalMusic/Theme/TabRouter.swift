import SwiftUI

/// Soft PASS tab IDs — Home is the default landing.
enum ChibiTab: Int, Hashable, Sendable {
    case home = 0
    case library = 1
    case nowPlaying = 2
    case playlists = 3
    case radio = 4
}

/// Shared tab selection so Home shortcuts can jump without a Sendable closure env key.
@Observable
@MainActor
final class TabRouter {
    var selected: ChibiTab = .home
}
