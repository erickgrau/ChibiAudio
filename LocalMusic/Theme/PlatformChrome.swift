import SwiftUI

#if os(iOS)
import UIKit
#else
import AppKit
#endif

// Cross-platform primitives shared by the iOS and Mac targets. Shared
// sources reference these instead of `UIImage`/`UIColor` and the iOS-only
// navigation chrome so one set of files compiles on both platforms.

#if os(iOS)
typealias PlatformImage = UIImage
typealias PlatformColor = UIColor
#else
typealias PlatformImage = NSImage
typealias PlatformColor = NSColor
#endif

extension PlatformImage {
    /// Wraps a decoded `CGImage` at the pixel size it was decoded to, so
    /// ImageIO downsampling work is preserved on both platforms.
    static func make(cgImage: CGImage, pixelSize: CGFloat) -> PlatformImage {
        #if os(iOS)
        PlatformImage(cgImage: cgImage)
        #else
        PlatformImage(cgImage: cgImage, size: NSSize(width: pixelSize, height: pixelSize))
        #endif
    }

    /// Backing `CGImage` for cross-platform CoreImage work.
    var platformCGImage: CGImage? {
        #if os(iOS)
        cgImage
        #else
        cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
    }
}

extension Image {
    /// `Image(uiImage:)` / `Image(nsImage:)` behind one name.
    init(platformImage: PlatformImage) {
        #if os(iOS)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}

/// Primary-screen backing scale for pixel-targeted artwork decodes.
enum PlatformDisplay {
    static var mainScale: CGFloat {
        #if os(iOS)
        UIScreen.main.scale
        #else
        NSScreen.main?.backingScaleFactor ?? 2.0
        #endif
    }
}

/// Nav-bar toolbar slots. iOS uses `topBarLeading`/`topBarTrailing`; the
/// Mac equivalents are `navigation` (leading) and `primaryAction` (trailing).
enum PlatformToolbar {
    static var leading: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }

    static var trailing: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }
}

extension View {
    /// Inline navigation-bar title. The modifier is iOS-only; the Mac
    /// target's window chrome sizes titles itself.
    @ViewBuilder
    func chibiInlineNavTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Glass navigation-bar background. `.navigationBar` placement is
    /// iOS-only; on the Mac the window chrome comes from `chibiCanvas`.
    @ViewBuilder
    func chibiNavChrome() -> some View {
        #if os(iOS)
        self
            .toolbarBackground(ChibiTheme.softGlass, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        #else
        self
        #endif
    }

    /// Compact `List` section spacing. `listSectionSpacing` is iOS-only;
    /// the Mac list style already tightens section gaps.
    @ViewBuilder
    func chibiCompactSectionSpacing() -> some View {
        #if os(iOS)
        self.listSectionSpacing(.compact)
        #else
        self
        #endif
    }
}