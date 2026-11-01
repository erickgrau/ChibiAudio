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
// MARK: - Sheets

/// How much room a sheet's content needs on the Mac.
///
/// macOS sizes a sheet window to its content's ideal size. A
/// `NavigationStack` around a `List`, `Form` or `ScrollView` has almost no
/// ideal height, so without an explicit frame the sheet collapses to the
/// toolbar (the 470 x 113 Settings and Up Next sheets). iOS presents sheets
/// at the system detent sizes, so these values only apply to the Mac.
enum ChibiSheetSize {
    /// Short pickers and sign-in flows.
    case compact
    /// Lists and forms.
    case regular
    /// Long-form reading: lyrics, release notes, the paywall.
    case large

    var minWidth: CGFloat {
        switch self {
        case .compact: 420
        case .regular: 520
        case .large: 560
        }
    }

    var idealWidth: CGFloat {
        switch self {
        case .compact: 460
        case .regular: 600
        case .large: 680
        }
    }

    /// Kept under the 600 pt minimum window height (less the title bar),
    /// so a sheet never hangs off a minimum-size window.
    var minHeight: CGFloat {
        switch self {
        case .compact: 360
        case .regular, .large: 420
        }
    }

    var idealHeight: CGFloat {
        switch self {
        case .compact: 440
        case .regular, .large: 520
        }
    }
}

extension View {
    /// Gives sheet content a usable, resizable size on the Mac. No-op on iOS.
    @ViewBuilder
    func chibiSheetFrame(_ size: ChibiSheetSize = .regular) -> some View {
        #if os(macOS)
        self.frame(
            minWidth: size.minWidth, idealWidth: size.idealWidth, maxWidth: 1_200,
            minHeight: size.minHeight, idealHeight: size.idealHeight, maxHeight: 1_000
        )
        #else
        self
        #endif
    }

    /// `.sheet(isPresented:)` with Mac content sizing. Every sheet in the
    /// app goes through this (or the `item:` variant) so no caller can
    /// regress to a collapsed Mac sheet.
    func chibiSheet<Content: View>(
        isPresented: Binding<Bool>,
        size: ChibiSheetSize = .regular,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            content().chibiSheetFrame(size)
        }
    }

    /// `.sheet(item:)` with Mac content sizing.
    func chibiSheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        size: ChibiSheetSize = .regular,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        sheet(item: item, onDismiss: onDismiss) { value in
            content(value).chibiSheetFrame(size)
        }
    }
}
