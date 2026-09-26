import Foundation
import Observation
import SwiftUI

enum AppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case light
    case dark
    case system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }
}

/// Light is the default. Dark is the existing Onyx look. System follows the device.
@Observable
@MainActor
final class AppearanceStore {
    private static let defaultsKey = "appearancePreference"

    var preference: AppearancePreference {
        didSet {
            UserDefaults.standard.set(preference.rawValue, forKey: Self.defaultsKey)
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch preference {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.defaultsKey),
           let stored = AppearancePreference(rawValue: raw) {
            preference = stored
        } else {
            preference = .light
        }
    }
}
