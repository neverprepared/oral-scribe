import XCTest
@testable import OralScribe

final class TranscriptEntryTests: XCTestCase {

    // MARK: - Initialisation

    func testInitSetsRequiredFields() {
        let entry = TranscriptEntry(text: "Hello", duration: 5.0)
        XCTAssertEqual(entry.text, "Hello")
        XCTAssertEqual(entry.duration, 5.0)
        XCTAssertNil(entry.processingMode)
        XCTAssertNil(entry.processingModel)
    }

    func testInitSetsOptionalFields() {
        let entry = TranscriptEntry(
            text: "Processed text",
            duration: 10.0,
            processingMode: "cleanup",
            processingModel: "llama3.2"
        )
        XCTAssertEqual(entry.processingMode, "cleanup")
        XCTAssertEqual(entry.processingModel, "llama3.2")
    }

    func testInitGeneratesUniqueIDs() {
        let e1 = TranscriptEntry(text: "A", duration: 1.0)
        let e2 = TranscriptEntry(text: "A", duration: 1.0)
        XCTAssertNotEqual(e1.id, e2.id)
    }

    func testInitSetsTimestamp() {
        let before = Date()
        let entry = TranscriptEntry(text: "Test", duration: 1.0)
        let after = Date()
        XCTAssertGreaterThanOrEqual(entry.timestamp, before)
        XCTAssertLessThanOrEqual(entry.timestamp, after)
    }

    // MARK: - Codable

    func testCodableRoundtrip() throws {
        let original = TranscriptEntry(
            text: "Roundtrip test",
            duration: 7.5,
            processingMode: "summarize",
            processingModel: "llama3.2"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TranscriptEntry.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.text, original.text)
        XCTAssertEqual(decoded.duration, original.duration)
        XCTAssertEqual(decoded.processingMode, original.processingMode)
        XCTAssertEqual(decoded.processingModel, original.processingModel)
    }

    func testCodableArrayRoundtrip() throws {
        let entries = (1...3).map { TranscriptEntry(text: "Entry \($0)", duration: Double($0)) }
        let data = try JSONEncoder().encode(entries)
        let decoded = try JSONDecoder().decode([TranscriptEntry].self, from: data)

        XCTAssertEqual(decoded.count, 3)
        for i in 0..<3 {
            XCTAssertEqual(decoded[i].text, entries[i].text)
            XCTAssertEqual(decoded[i].id, entries[i].id)
        }
    }

    func testCodableWithNilOptionals() throws {
        let entry = TranscriptEntry(text: "No processing", duration: 2.0)
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(TranscriptEntry.self, from: data)

        XCTAssertNil(decoded.processingMode)
        XCTAssertNil(decoded.processingModel)
    }

    func testCodablePreservesUnicode() throws {
        let entry = TranscriptEntry(text: "Hello 🌍 Привет 中文", duration: 1.0)
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(TranscriptEntry.self, from: data)
        XCTAssertEqual(decoded.text, "Hello 🌍 Привет 中文")
    }

    func testCodablePreservesSpecialCharacters() throws {
        let entry = TranscriptEntry(text: "Line 1\nLine 2\tTabbed \"quoted\"", duration: 1.0)
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(TranscriptEntry.self, from: data)
        XCTAssertEqual(decoded.text, entry.text)
    }
}
