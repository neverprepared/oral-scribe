import Foundation
import CryptoKit
import Security

// MARK: - History Store
//
// Persists transcript history as AES-256-GCM encrypted data in UserDefaults.
// The symmetric key is stored in the Keychain with kSecAttrAccessibleAfterFirstUnlock
// so it survives sleep/wake and login-item launches, but is never written to disk
// in plaintext.
//
// On first run after upgrading from a plaintext build, any existing plaintext history
// is transparently migrated to encrypted storage.

enum HistoryStore {

    // MARK: - Constants

    private static let encryptedKey    = "transcriptHistoryEncrypted"
    private static let plaintextKey    = "transcriptHistory"          // legacy / migration
    private static let keychainService = "com.oralscribe.app"
    private static let keychainAccount = "history-encryption-key"

    /// Injectable UserDefaults — override in tests to avoid polluting user preferences.
    static var defaults: UserDefaults = .standard

    // MARK: - Public API

    static func load() -> [TranscriptEntry] {
        guard let key = loadOrCreateKey() else {
            print("OralScribe: HistoryStore could not obtain encryption key — history unavailable")
            return []
        }

        // Encrypted path (normal)
        if let blob = defaults.data(forKey: encryptedKey) {
            if let entries = decrypt(blob, using: key) {
                return entries
            }
            // Corrupted blob — clear and start fresh
            print("OralScribe: HistoryStore decryption failed, clearing history")
            defaults.removeObject(forKey: encryptedKey)
            return []
        }

        // Migration: plaintext data from a previous build
        if let plainData = defaults.data(forKey: plaintextKey),
           let entries = try? JSONDecoder().decode([TranscriptEntry].self, from: plainData) {
            save(entries)
            defaults.removeObject(forKey: plaintextKey)
            return entries
        }

        return []
    }

    static func save(_ entries: [TranscriptEntry]) {
        guard let key = loadOrCreateKey(),
              let json = try? JSONEncoder().encode(entries),
              let blob = encrypt(json, using: key) else {
            print("OralScribe: HistoryStore could not encrypt history")
            return
        }
        defaults.set(blob, forKey: encryptedKey)
    }

    static func clear() {
        defaults.removeObject(forKey: encryptedKey)
        defaults.removeObject(forKey: plaintextKey)
    }

    // MARK: - Encryption / Decryption (internal for testability)

    static func encrypt(_ data: Data, using key: SymmetricKey) -> Data? {
        guard let box = try? AES.GCM.seal(data, using: key) else { return nil }
        return box.combined   // 12-byte nonce ‖ ciphertext ‖ 16-byte tag
    }

    static func decrypt(_ data: Data, using key: SymmetricKey) -> [TranscriptEntry]? {
        guard let box       = try? AES.GCM.SealedBox(combined: data),
              let plainData = try? AES.GCM.open(box, using: key),
              let entries   = try? JSONDecoder().decode([TranscriptEntry].self, from: plainData)
        else { return nil }
        return entries
    }

    // MARK: - Keychain Key Management

    private static func loadOrCreateKey() -> SymmetricKey? {
        if let key = readKey() { return key }
        let newKey = SymmetricKey(size: .bits256)
        return writeKey(newKey) ? newKey : nil
    }

    private static func readKey() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass       as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData  as String: true,
            kSecMatchLimit  as String: kSecMatchLimitOne
        ]
        var item: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return SymmetricKey(data: data)
    }

    private static func writeKey(_ key: SymmetricKey) -> Bool {
        let keyData = key.withUnsafeBytes { Data($0) }
        let attrs: [String: Any] = [
            kSecClass            as String: kSecClassGenericPassword,
            kSecAttrService      as String: keychainService,
            kSecAttrAccount      as String: keychainAccount,
            kSecValueData        as String: keyData,
            kSecAttrAccessible   as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(attrs as CFDictionary, nil)
        if status != errSecSuccess {
            print("OralScribe: HistoryStore failed to store key in Keychain (\(status))")
        }
        return status == errSecSuccess
    }
}
