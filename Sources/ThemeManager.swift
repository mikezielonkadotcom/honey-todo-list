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

    /// Warm cream in light mode, warm near-black in dark mode.
    static let appBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            ? NSColor(srgbRed: 0.105, green: 0.097, blue: 0.087, alpha: 1)
            : NSColor(srgbRed: 0.992, green: 0.972, blue: 0.928, alpha: 1)
    })

    /// Card surface — pure white in light mode, slightly elevated warm grey in dark.
    static let cardBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            ? NSColor(srgbRed: 0.165, green: 0.155, blue: 0.142, alpha: 1)
            : NSColor.white
    })

    static let cardHover = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            ? NSColor(srgbRed: 0.205, green: 0.190, blue: 0.172, alpha: 1)
            : NSColor(srgbRed: 1.0, green: 0.992, blue: 0.972, alpha: 1)
    })

    /// Soft amber pill for overdue — warm warning, not alarm-red.
    static let overdueBg = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            ? NSColor(srgbRed: 0.45, green: 0.22, blue: 0.05, alpha: 1)
            : NSColor(srgbRed: 1.0, green: 0.92, blue: 0.83, alpha: 1)
    })
    static let overdueFg = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            ? NSColor(srgbRed: 1.0, green: 0.78, blue: 0.55, alpha: 1)
            : NSColor(srgbRed: 0.62, green: 0.32, blue: 0.05, alpha: 1)
    })

    /// 8-color palette for list accent stripes. Picked by hashing the list name.
    static let listPalette: [Color] = [
        Color(red: 0.93, green: 0.62, blue: 0.20), // honey
        Color(red: 0.91, green: 0.43, blue: 0.42), // coral
        Color(red: 0.36, green: 0.71, blue: 0.55), // mint
        Color(red: 0.55, green: 0.50, blue: 0.85), // lavender
        Color(red: 0.34, green: 0.65, blue: 0.84), // sky
        Color(red: 0.95, green: 0.55, blue: 0.36), // peach
        Color(red: 0.55, green: 0.66, blue: 0.40), // sage
        Color(red: 0.84, green: 0.49, blue: 0.65)  // rose
    ]

    static func forList(_ name: String?) -> Color {
        guard let n = name, !n.isEmpty else { return Color.honey.opacity(0.5) }
        var h: UInt32 = 5381
        for byte in n.utf8 { h = (h &* 33) &+ UInt32(byte) }
        return listPalette[Int(h % UInt32(listPalette.count))]
    }
}
