import Foundation
import Security

/// File-based secret store. Replaces the previous Keychain implementation
/// because Keychain ACLs are pinned to a binary's code signature, which
/// causes a re-prompt on every app update. The token lives in
/// ~/Library/Application Support/Honey Todo List/token with 0600 perms.
/// FileVault provides encryption-at-rest.
///
/// Class name kept as KeychainStore so call sites don't need to change.
final class KeychainStore: @unchecked Sendable {
    static let shared = KeychainStore()
    private let service = "com.mikezielonka.honey-todo-list"
    private let account = "clickup-personal-token"

    private let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Honey Todo List", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("token")
    }()

    var token: String? {
        get {
            if let v = readFile() { return v }
            // First-run migration from old Keychain entry.
            if let legacy = readKeychain() {
                writeFile(legacy)
                deleteKeychain()
                return legacy
            }
            return nil
        }
        set {
            if let v = newValue, !v.isEmpty {
                writeFile(v)
            } else {
                try? FileManager.default.removeItem(at: fileURL)
            }
            deleteKeychain()
        }
    }

    // MARK: - File backing

    private func readFile() -> String? {
        guard let data = try? Data(contentsOf: fileURL),
              let s = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func writeFile(_ value: String) {
        let data = Data(value.utf8)
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    // MARK: - Legacy Keychain (read once, then delete)

    private func readKeychain() -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }

    private func deleteKeychain() {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(q as CFDictionary)
    }
}
