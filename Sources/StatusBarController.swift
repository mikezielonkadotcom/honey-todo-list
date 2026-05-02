import AppKit

@MainActor
final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private let tasksWindow: TasksWindow
    private var preferencesWindow: PreferencesWindow?

    init(tasksWindow: TasksWindow) {
        self.tasksWindow = tasksWindow
        super.init()
        setup()
    }

    private func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        if let img = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Honey Todo List") {
            img.isTemplate = true
            button.image = img
        } else {
            button.title = "🍯"
        }
        button.toolTip = "Honey Todo List"
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.action = #selector(handleClick(_:))
        button.target = self
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showMenu()
        } else {
            tasksWindow.toggleWindow()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(item("Show Window", #selector(openWindow)))
        menu.addItem(item("Refresh", #selector(refresh)))
        menu.addItem(.separator())
        menu.addItem(item("Check for Updates…", #selector(checkForUpdates)))
        menu.addItem(item("Preferences…", #selector(openPreferences), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Quit", #selector(quit), key: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc private func openWindow() { tasksWindow.showWindow() }
    @objc private func refresh() { globalTaskStore?.refresh() }
    @objc private func openPreferences() { openPreferencesFromMenu() }
    @objc private func checkForUpdates() { UpdateManager.shared.checkForUpdatesInteractive() }
    @objc private func quit() { NSApp.terminate(nil) }

    func openPreferencesFromMenu() {
        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindow(store: globalTaskStore!)
        }
        preferencesWindow?.show()
    }
}
