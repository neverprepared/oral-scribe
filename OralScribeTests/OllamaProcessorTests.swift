import XCTest
@testable import OralScribe

final class OllamaProcessorTests: XCTestCase {

    private var processor: OllamaProcessor!

    override func setUp() {
        super.setUp()
        processor = OllamaProcessor()
    }

    // MARK: - stripPreamble

    func testStripsHereIs() {
        XCTAssertEqual(
            processor.stripPreamble("Here is the summary: Actual content"),
            "Actual content"
        )
    }

    func testStripsHeresThe() {
        XCTAssertEqual(
            processor.stripPreamble("Here's the result: The meeting went well"),
            "The meeting went well"
        )
    }

    func testStripsHereIsTheFormatted() {
        XCTAssertEqual(
            processor.stripPreamble("Here is the formatted text: Clean version"),
            "Clean version"
        )
    }

    func testStripsHereSTheCleanedUp() {
        XCTAssertEqual(
            processor.stripPreamble("Here's the cleaned up version: Fixed grammar here"),
            "Fixed grammar here"
        )
    }

    func testPreservesTextWithoutPreamble() {
        let text = "The meeting covered three main topics."
        XCTAssertEqual(processor.stripPreamble(text), text)
    }

    func testPreservesActionItemsWithColon() {
        // Colon present but doesn't start with "here"
        let text = "Action items: review PR, update docs"
        XCTAssertEqual(processor.stripPreamble(text), text)
    }

    func testPreservesTimestampColon() {
        let text = "At 10:30 the team reviewed the roadmap"
        XCTAssertEqual(processor.stripPreamble(text), text)
    }

    func testReturnsOriginalWhenNothingAfterColon() {
        // Edge case: trailing colon with nothing after
        let text = "Here is the summary:"
        XCTAssertEqual(processor.stripPreamble(text), text)
    }

    func testPreservesEmptyString() {
        XCTAssertEqual(processor.stripPreamble(""), "")
    }

    func testPreservesContentWithMultipleColons() {
        // Second colon — should strip up to the first colon after "here"
        XCTAssertEqual(
            processor.stripPreamble("Here is it: Part one: Part two"),
            "Part one: Part two"
        )
    }

    func testStripsAndTrimsLeadingWhitespace() {
        XCTAssertEqual(
            processor.stripPreamble("Here is the summary:   Leading spaces trimmed"),
            "Leading spaces trimmed"
        )
    }

    // MARK: - Host Validation (initialisation doesn't crash)

    func testLocalhostInitialises() {
        let p = OllamaProcessor(host: "http://localhost:11434")
        XCTAssertEqual(p.host, "http://localhost:11434")
    }

    func test127001Initialises() {
        let p = OllamaProcessor(host: "http://127.0.0.1:11434")
        XCTAssertEqual(p.host, "http://127.0.0.1:11434")
    }

    func testRemoteHostInitialises() {
        // Should initialise without crashing (warning is printed to console)
        let p = OllamaProcessor(host: "http://192.168.1.100:11434")
        XCTAssertEqual(p.host, "http://192.168.1.100:11434")
    }

    func testDefaultHostIsLocalhost() {
        let p = OllamaProcessor()
        XCTAssertEqual(p.host, "http://localhost:11434")
    }

    func testDefaultModelIsLlama() {
        let p = OllamaProcessor()
        XCTAssertEqual(p.model, "llama3.2")
    }
}
