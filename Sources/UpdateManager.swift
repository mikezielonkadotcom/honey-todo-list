import AppKit

@MainActor
final class UpdateManager {
    static let shared = UpdateManager()

    private let repoOwner = "mikezielonkadotcom"
    private let repoName = "honey-todo-list"
    private var isChecking = false

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private var apiURL: URL {
        URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
    }

    func checkForUpdatesInBackground() { checkForUpdates(silent: true) }
    func checkForUpdatesInteractive() { checkForUpdates(silent: false) }

    private func checkForUpdates(silent: Bool) {
        guard !isChecking else { return }
        isChecking = true

        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async { @MainActor in
                self?.isChecking = false
                self?.handleResponse(data: data, response: response, error: error, silent: silent)
            }
        }.resume()
    }

    private func handleResponse(data: Data?, response: URLResponse?, error: Error?, silent: Bool) {
        if let error = error {
            if !silent { showAlert(title: "Update Check Failed", message: "Could not reach GitHub: \(error.localizedDescription)") }
            return
        }
        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String else {
            if !silent { showAlert(title: "Update Check Failed", message: "Could not parse release information from GitHub.") }
            return
        }
        let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        if isNewerVersion(remote: remoteVersion, current: currentVersion) {
            let body = json["body"] as? String ?? ""
            promptForUpdate(version: remoteVersion, releaseNotes: body, assets: json["assets"] as? [[String: Any]] ?? [])
        } else if !silent {
            showAlert(title: "Up to Date", message: "You're running the latest version (\(currentVersion)).")
        }
    }

    private func promptForUpdate(version: String, releaseNotes: String, assets: [[String: Any]]) {
        guard let asset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true }),
              let downloadURLString = asset["browser_download_url"] as? String,
              let downloadURL = URL(string: downloadURLString) else {
            showAlert(title: "Update Available (v\(version))", message: "A new version is available but no downloadable package was found.\n\nPlease update manually from GitHub.")
            return
        }

        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "Version \(version) is available (you have \(currentVersion)).\n\n\(releaseNotes.prefix(300))"
        alert.addButton(withTitle: "Update Now")
        alert.addButton(withTitle: "Later")
        alert.alertStyle = .informational

        if alert.runModal() == .alertFirstButtonReturn {
            downloadAndInstall(url: downloadURL, version: version)
        }
    }

    private func downloadAndInstall(url: URL, version: String) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Updating…"
        window.center()
        let label = NSTextField(labelWithString: "Downloading v\(version)…")
        label.frame = NSRect(x: 20, y: 40, width: 280, height: 20)
        let progress = NSProgressIndicator(frame: NSRect(x: 20, y: 15, width: 280, height: 20))
        progress.style = .bar
        progress.isIndeterminate = true
        progress.startAnimation(nil)
        window.contentView?.addSubview(label)
        window.contentView?.addSubview(progress)
        window.makeKeyAndOrderFront(nil)

        URLSession.shared.downloadTask(with: url) { [weak self] tempURL, _, error in
            DispatchQueue.main.async { @MainActor in
                window.close()
                if let error = error {
                    self?.showAlert(title: "Download Failed", message: error.localizedDescription)
                    return
                }
                guard let tempURL = tempURL else {
                    self?.showAlert(title: "Download Failed", message: "No file was downloaded.")
                    return
                }
                self?.installUpdate(from: tempURL)
            }
        }.resume()
    }

    private func installUpdate(from zipURL: URL) {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("HoneyTodoList-update-\(UUID().uuidString)")

        do {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let zipDest = tempDir.appendingPathComponent("update.zip")
            try fm.copyItem(at: zipURL, to: zipDest)

            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip.arguments = ["-o", zipDest.path, "-d", tempDir.path]
            try unzip.run()
            unzip.waitUntilExit()
            guard unzip.terminationStatus == 0 else {
                showAlert(title: "Update Failed", message: "Could not unzip the update package.")
                return
            }

            let contents = try fm.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            guard let newApp = contents.first(where: { $0.pathExtension == "app" }) else {
                showAlert(title: "Update Failed", message: "No .app found in the update package.")
                return
            }

            let currentAppURL = Bundle.main.bundleURL
            let backupURL = tempDir.appendingPathComponent("HoneyTodoList-old.app")
            try fm.moveItem(at: currentAppURL, to: backupURL)
            try fm.copyItem(at: newApp, to: currentAppURL)

            let xattr = Process()
            xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattr.arguments = ["-cr", currentAppURL.path]
            try? xattr.run()
            xattr.waitUntilExit()

            let relaunch = Process()
            relaunch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            relaunch.arguments = ["-n", currentAppURL.path]
            try relaunch.run()

            NSApp.terminate(nil)
        } catch {
            showAlert(title: "Update Failed", message: error.localizedDescription)
        }
    }

    private func isNewerVersion(remote: String, current: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let c = current.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, c.count) {
            let rv = i < r.count ? r[i] : 0
            let cv = i < c.count ? c[i] : 0
            if rv > cv { return true }
            if rv < cv { return false }
        }
        return false
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
