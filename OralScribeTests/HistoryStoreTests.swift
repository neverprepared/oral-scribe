import XCTest
import CryptoKit
@testable import OralScribe

final class HistoryStoreTests: XCTestCase {

    private static let testSuiteName = "com.oralscribe.tests.history"

    override func setUp() {
        super.setUp()
        // Point HistoryStore at an isolated UserDefaults suite and in-memory Keychain
        let suite = UserDefaults(suiteName: Self.testSuiteName)!
        suite.removePersistentDomain(forName: Self.testSuiteName)
        HistoryStore.defaults = suite
        HistoryStore.keychain = InMemoryKeychain()
    }

    override func tearDown() {
        HistoryStore.clear()
        HistoryStore.defaults.removePersistentDomain(forName: Self.testSuiteName)
        HistoryStore.defaults = .standard
        HistoryStore.keychain = DefaultKeychainStore()
        super.tearDown()
    }

    // MARK: - encrypt / decrypt

    func testEncryptReturnsData() {
        let key = SymmetricKey(size: .bits256)
        let data = "Hello".data(using: .utf8)!
        XCTAssertNotNil(HistoryStore.encrypt(data, using: key))
    }

    func testEncryptedDataDiffersFromPlaintext() {
        let key = SymmetricKey(size: .bits256)
        let data = "Hello".data(using: .utf8)!
        XCTAssertNotEqual(HistoryStore.encrypt(data, using: key), data)
    }

    func testEncryptDecryptRoundtrip() throws {
        let key = SymmetricKey(size: .bits256)
        let entries = [TranscriptEntry(text: "Secret transcript", duration: 5.0)]
        let json = try JSONEncoder().encode(entries)

        let encrypted = try XCTUnwrap(HistoryStore.encrypt(json, using: key))
        let decrypted = HistoryStore.decrypt(encrypted, using: key)

        XCTAssertEqual(decrypted?.count, 1)
        XCTAssertEqual(decrypted?.first?.text, "Secret transcript")
    }

    func testDecryptWithWrongKeyReturnsNil() throws {
        let key1 = SymmetricKey(size: .bits256)
        let key2 = SymmetricKey(size: .bits256)
        let json = try JSONEncoder().encode([TranscriptEntry(text: "Secret", duration: 1.0)])
        let encrypted = try XCTUnwrap(HistoryStore.encrypt(json, using: key1))

        XCTAssertNil(HistoryStore.decrypt(encrypted, using: key2))
    }

    func testDecryptCorruptedDataReturnsNil() {
        let key = SymmetricKey(size: .bits256)
        XCTAssertNil(HistoryStore.decrypt(Data([0x00, 0x01, 0x02, 0x03]), using: key))
    }

    func testEncryptProducesUniqueNoncesEachCall() {
        let key = SymmetricKey(size: .bits256)
        let data = "Same input".data(using: .utf8)!
        let enc1 = HistoryStore.encrypt(data, using: key)
        let enc2 = HistoryStore.encrypt(data, using: key)
        XCTAssertNotEqual(enc1, enc2, "AES-GCM must use a unique nonce per encryption")
    }

    func testDecryptPreservesAllFields() throws {
        let key = SymmetricKey(size: .bits256)
        let original = TranscriptEntry(
            text: "Full entry",
            duration: 12.5,
            processingMode: "cleanup",
            processingModel: "llama3.2"
        )
        let json = try JSONEncoder().encode([original])
        let encrypted = try XCTUnwrap(HistoryStore.encrypt(json, using: key))
        let decoded = try XCTUnwrap(HistoryStore.decrypt(encrypted, using: key)?.first)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.text, original.text)
        XCTAssertEqual(decoded.duration, original.duration)
        XCTAssertEqual(decoded.processingMode, original.processingMode)
        XCTAssertEqual(decoded.processingModel, original.processingModel)
    }

    // MARK: - save / load / clear

    func testLoadReturnsEmptyWhenNothingSaved() {
        XCTAssertTrue(HistoryStore.load().isEmpty)
    }

    func testSaveAndLoad() {
        let entries = [TranscriptEntry(text: "Test transcript", duration: 3.0)]
        HistoryStore.save(entries)
        let loaded = HistoryStore.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.text, "Test transcript")
    }

    func testSavePreservesMetadata() {
        let entry = TranscriptEntry(
            text: "Processed",
            duration: 8.0,
            processingMode: "cleanup",
            processingModel: "llama3.2"
        )
        HistoryStore.save([entry])
        let loaded = HistoryStore.load()
        XCTAssertEqual(loaded.first?.processingMode, "cleanup")
        XCTAssertEqual(loaded.first?.processingModel, "llama3.2")
    }

    func testClearRemovesAllEntries() {
        HistoryStore.save([TranscriptEntry(text: "To be cleared", duration: 1.0)])
        HistoryStore.clear()
        XCTAssertTrue(HistoryStore.load().isEmpty)
    }

    func testSaveMultipleEntriesPreservesOrder() {
        let entries = (1...5).map { TranscriptEntry(text: "Entry \($0)", duration: Double($0)) }
        HistoryStore.save(entries)
        let loaded = HistoryStore.load()
        XCTAssertEqual(loaded.count, 5)
        for i in 0..<5 {
            XCTAssertEqual(loaded[i].text, entries[i].text)
        }
    }

    func testSaveOverwritesPreviousSave() {
        HistoryStore.save([TranscriptEntry(text: "Old", duration: 1.0)])
        HistoryStore.save([TranscriptEntry(text: "New", duration: 2.0)])
        let loaded = HistoryStore.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.text, "New")
    }

    func testDataIsStoredEncrypted() {
        HistoryStore.save([TranscriptEntry(text: "Secret text", duration: 1.0)])
        let blob = HistoryStore.defaults.data(forKey: "transcriptHistoryEncrypted")
        XCTAssertNotNil(blob, "Encrypted blob should exist in UserDefaults")
        // The plaintext should not appear verbatim in the ciphertext
        let asString = String(data: blob!, encoding: .utf8)
        XCTAssertFalse(asString?.contains("Secret text") ?? false,
                       "Plaintext should not appear in the encrypted blob")
    }

    func testNoPlainfextKeyAfterSave() {
        HistoryStore.save([TranscriptEntry(text: "Test", duration: 1.0)])
        XCTAssertNil(HistoryStore.defaults.data(forKey: "transcriptHistory"),
                     "Legacy plaintext key must not be written by save()")
    }

    // MARK: - Migration

    func testMigratesPlaintextToEncrypted() throws {
        let entries = [TranscriptEntry(text: "Legacy entry", duration: 2.0)]
        let json = try JSONEncoder().encode(entries)
        HistoryStore.defaults.set(json, forKey: "transcriptHistory")

        let loaded = HistoryStore.load()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.text, "Legacy entry")
        XCTAssertNil(HistoryStore.defaults.data(forKey: "transcriptHistory"),
                     "Plaintext key should be removed after migration")
        XCTAssertNotNil(HistoryStore.defaults.data(forKey: "transcriptHistoryEncrypted"),
                        "Encrypted key should exist after migration")
    }

    func testMigrationPreservesAllFields() throws {
        let entry = TranscriptEntry(
            text: "Legacy",
            duration: 5.0,
            processingMode: "summarize",
            processingModel: "llama3.2"
        )
        let json = try JSONEncoder().encode([entry])
        HistoryStore.defaults.set(json, forKey: "transcriptHistory")

        let loaded = HistoryStore.load()
        XCTAssertEqual(loaded.first?.processingMode, "summarize")
        XCTAssertEqual(loaded.first?.processingModel, "llama3.2")
        XCTAssertEqual(loaded.first?.text, "Legacy")
    }

    func testMigrationIsIdempotent() throws {
        let entries = [TranscriptEntry(text: "Migrate me", duration: 1.0)]
        let json = try JSONEncoder().encode(entries)
        HistoryStore.defaults.set(json, forKey: "transcriptHistory")

        _ = HistoryStore.load()  // first load triggers migration
        let secondLoad = HistoryStore.load()  // second load reads from encrypted store

        XCTAssertEqual(secondLoad.count, 1)
        XCTAssertEqual(secondLoad.first?.text, "Migrate me")
    }
}

// MARK: - Test Helpers

final class InMemoryKeychain: KeychainStore {
    private var storedKey: SymmetricKey?

    func read() -> SymmetricKey? { storedKey }

    func write(_ key: SymmetricKey) -> Bool {
        storedKey = key
        return true
    }
}
