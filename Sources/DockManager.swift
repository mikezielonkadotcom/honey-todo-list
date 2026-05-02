import AppKit

@MainActor
enum DockManager {
    private static let key = "showInDock"

    static func apply() {
        if UserDefaults.standard.object(forKey: key) == nil {
            UserDefaults.standard.set(true, forKey: key)
        }
        setPolicy(show: UserDefaults.standard.bool(forKey: key))
    }

    static func setDockVisibility(show: Bool) {
        UserDefaults.standard.set(show, forKey: key)
        setPolicy(show: show)
    }

    static var isShowingInDock: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    private static func setPolicy(show: Bool) {
        NSApp.setActivationPolicy(show ? .regular : .accessory)
        if !show {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { @MainActor in
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
