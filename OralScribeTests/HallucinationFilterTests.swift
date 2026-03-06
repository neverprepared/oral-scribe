import XCTest
@testable import OralScribe

final class HallucinationFilterTests: XCTestCase {

    // MARK: - Individual Patterns

    func testRemovesThankYouForWatching() {
        XCTAssertEqual(filter("Real content. Thank you for watching"), "Real content")
    }

    func testRemovesThanksForWatching() {
        XCTAssertEqual(filter("Notes here. Thanks for watching"), "Notes here")
    }

    func testRemovesThankYouForListening() {
        XCTAssertEqual(filter("Meeting summary. Thank you for listening"), "Meeting summary")
    }

    func testRemovesThanksForListening() {
        XCTAssertEqual(filter("Key points. Thanks for listening"), "Key points")
    }

    func testRemovesPleaseSubscribe() {
        XCTAssertEqual(filter("Today we covered. Please subscribe"), "Today we covered")
    }

    func testRemovesDontForgetToSubscribe() {
        XCTAssertEqual(filter("Great session. Don't forget to subscribe"), "Great session")
    }

    func testRemovesLikeAndSubscribe() {
        XCTAssertEqual(filter("Discussion ended. Like and subscribe"), "Discussion ended")
    }

    func testRemovesSeeYouNextTime() {
        XCTAssertEqual(filter("That covers it. See you next time"), "That covers it")
    }

    func testRemovesAllRightsReserved() {
        XCTAssertEqual(filter("Content. All rights reserved"), "Content")
    }

    func testRemovesTranscribedBy() {
        XCTAssertEqual(filter("Transcript. Transcribed by"), "Transcript")
    }

    func testRemovesSubtitlesBy() {
        XCTAssertEqual(filter("Content. Subtitles by"), "Content")
    }

    func testRemovesCaptionsBy() {
        XCTAssertEqual(filter("Content. Captions by"), "Content")
    }

    func testRemovesThankYouVeryMuch() {
        XCTAssertEqual(filter("Discussion. Thank you very much"), "Discussion")
    }

    func testRemovesThankYouSoMuch() {
        XCTAssertEqual(filter("Wrap up. Thank you so much"), "Wrap up")
    }

    // MARK: - Regex Patterns

    func testRemovesThankYouWithPeriod() {
        XCTAssertEqual(filter("Good meeting. Thank you."), "Good meeting")
    }

    func testRemovesThanksAlone() {
        XCTAssertEqual(filter("That's all. Thanks"), "That's all")
    }

    func testRemovesLetsGo() {
        XCTAssertEqual(filter("Starting now. Let's go"), "Starting now")
    }

    func testRemovesLetsGoWithExclamation() {
        XCTAssertEqual(filter("Here we go. Let's go!"), "Here we go")
    }

    // MARK: - Multiple Trailing Hallucinations

    func testRemovesMultipleTrailingHallucinations() {
        XCTAssertEqual(
            filter("Real content. Thank you for watching. Please subscribe"),
            "Real content"
        )
    }

    func testRemovesThreeTrailingHallucinations() {
        XCTAssertEqual(
            filter("Actual notes. Thanks for watching. Like and subscribe. See you next time"),
            "Actual notes"
        )
    }

    // MARK: - Case Insensitivity

    func testUpperCaseDetected() {
        XCTAssertEqual(filter("Content. THANK YOU FOR WATCHING"), "Content")
    }

    func testMixedCaseDetected() {
        XCTAssertEqual(filter("Content. Thank You For Watching"), "Content")
    }

    // MARK: - Non-Hallucination Content Preserved

    func testPreservesNormalContent() {
        let text = "The project deadline is next Friday"
        XCTAssertEqual(filter(text), text)
    }

    func testPreservesContentContainingThankKeyword() {
        // "thank" appears but not as a trailing hallucination phrase
        let text = "We should thank the team for their contribution"
        XCTAssertEqual(filter(text), text)
    }

    func testPreservesMultiSentenceContent() {
        let text = "First point. Second point. Third point"
        XCTAssertEqual(filter(text), text)
    }

    // MARK: - Edge Cases

    func testEmptyStringReturnsEmpty() {
        XCTAssertEqual(filter(""), "")
    }

    func testAllHallucinationsProducesEmpty() {
        XCTAssertEqual(filter("Thank you for watching. Please subscribe"), "")
    }

    func testSingleHallucinationAloneProducesEmpty() {
        XCTAssertEqual(filter("Thank you for watching"), "")
    }

    // MARK: - Helper

    private func filter(_ text: String) -> String {
        SwiftWhisperEngine.removeTrailingHallucinations(text)
    }
}
