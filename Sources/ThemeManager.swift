import AppKit
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
    fileprivate var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    private let key = "appTheme"

    @Published var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: key)
            apply()
        }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: key) ?? AppTheme.system.rawValue
        self.theme = AppTheme(rawValue: raw) ?? .system
    }

    func apply() {
        NSApp.appearance = theme.nsAppearance
    }
}

extension Color {
    /// Brand honey-amber. Same hue as the app icon's deep amber.
    static let honey = Color(red: 0.84, green: 0.57, blue: 0.12)
    static let honeyLight = Color(red: 1.0, green: 0.83, blue: 0.38)
    static let honeyDark = Color(red: 0.55, green: 0.30, blue: 0.05)
}
