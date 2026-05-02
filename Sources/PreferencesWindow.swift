import AppKit
import SwiftUI

@MainActor
final class PreferencesWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let store: TaskStore

    init(store: TaskStore) {
        self.store = store
    }

    func show() {
        if window == nil { build() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func build() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "Preferences"
        w.isReleasedWhenClosed = false
        w.center()
        w.delegate = self

        let host = NSHostingView(rootView: PreferencesView(store: store))
        w.contentView = host

        self.window = w
    }
}

struct PreferencesView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject private var theme = ThemeManager.shared
    @State private var token: String = KeychainStore.shared.token ?? ""
    @State private var showInDock: Bool = DockManager.isShowingInDock
    @State private var todayOn: Bool = TaskStore.loadEnabledTabs().contains(.today)
    @State private var tomorrowOn: Bool = TaskStore.loadEnabledTabs().contains(.tomorrow)
    @State private var allOn: Bool = TaskStore.loadEnabledTabs().contains(.all)
    @State private var saved: Bool = false

    var body: some View {
        Form {
            Section("ClickUp") {
                SecureField("Personal API Token (pk_…)", text: $token)
                Text("Generate at ClickUp → Settings → Apps → API Token. Stored in macOS Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Tabs") {
                Toggle("Today", isOn: $todayOn)
                Toggle("Tomorrow", isOn: $tomorrowOn)
                Toggle("All Due", isOn: $allOn)
            }
            Section("Appearance") {
                Picker("Theme", selection: $theme.theme) {
                    ForEach(AppTheme.allCases) { t in
                        Text(t.label).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Show in Dock", isOn: $showInDock)
                    .help("When off, Honey Todo List runs as a menu bar app only.")
            }
            Section {
                HStack {
                    Spacer()
                    if saved {
                        Text("Saved").foregroundStyle(.secondary).font(.caption)
                    }
                    Button("Save") { save() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 460)
        .onChange(of: showInDock) { _, newValue in
            DockManager.setDockVisibility(show: newValue)
        }
    }

    private func save() {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        KeychainStore.shared.token = trimmed.isEmpty ? nil : trimmed
        store.setTabEnabled(.today, todayOn)
        store.setTabEnabled(.tomorrow, tomorrowOn)
        store.setTabEnabled(.all, allOn)
        DockManager.setDockVisibility(show: showInDock)
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { saved = false }
        if !trimmed.isEmpty {
            store.refresh()
            globalTasksWindow?.showWindow()
        }
    }
}
