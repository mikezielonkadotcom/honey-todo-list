import AppKit
import SwiftUI

@MainActor
final class TasksWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let store: TaskStore

    init(store: TaskStore) {
        self.store = store
    }

    func showWindow() {
        if window == nil { build() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func toggleWindow() {
        if let w = window, w.isVisible {
            w.orderOut(nil)
        } else {
            showWindow()
        }
    }

    private func build() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.title = "Honey Todo List"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.styleMask.insert(.fullSizeContentView)
        w.standardWindowButton(.zoomButton)?.isEnabled = true
        w.center()
        w.setFrameAutosaveName("HoneyTodoMain")
        w.delegate = self

        let host = NSHostingView(rootView: TasksView(store: store))
        w.contentView = host

        self.window = w
    }

    func windowWillClose(_ notification: Notification) {
        // keep instance alive for next show
    }
}
