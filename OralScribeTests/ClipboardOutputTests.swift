import XCTest
import AppKit
@testable import OralScribe

final class ClipboardOutputTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Clear clipboard and internal tracking state before each test
        NSPasteboard.general.clearContents()
        ClipboardOutput.clearIfOurs()
    }

    override func tearDown() {
        NSPasteboard.general.clearContents()
        super.tearDown()
    }

    // MARK: - write()

    func testWriteSetsClipboard() {
        ClipboardOutput.write("Hello, clipboard!")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Hello, clipboard!")
    }

    func testWriteOverwritesPreviousContent() {
        ClipboardOutput.write("First")
        ClipboardOutput.write("Second")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Second")
    }

    func testWriteUnicode() {
        ClipboardOutput.write("Hello 🌍")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Hello 🌍")
    }

    func testWriteEmptyString() {
        ClipboardOutput.write("")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "")
    }

    // MARK: - clearIfOurs()

    func testClearIfOursClearsWhenContentMatches() {
        ClipboardOutput.write("Our text")
        ClipboardOutput.clearIfOurs()
        XCTAssertNil(NSPasteboard.general.string(forType: .string))
    }

    func testClearIfOursDoesNotClearWhenUserChangedClipboard() {
        ClipboardOutput.write("Our text")

        // Simulate user copying something else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("User's text", forType: .string)

        ClipboardOutput.clearIfOurs()

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "User's text")
    }

    func testClearIfOursNoopsWhenNeverWrote() {
        NSPasteboard.general.setString("External text", forType: .string)
        ClipboardOutput.clearIfOurs()
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "External text")
    }

    func testClearIfOursResetsInternalState() {
        ClipboardOutput.write("Our text")
        ClipboardOutput.clearIfOurs()

        // After clearing, a new external string should not be cleared
        NSPasteboard.general.setString("New external text", forType: .string)
        ClipboardOutput.clearIfOurs()

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "New external text")
    }

    func testSecondClearAfterMatchIsNoop() {
        ClipboardOutput.write("Our text")
        ClipboardOutput.clearIfOurs()  // clears
        NSPasteboard.general.setString("Something else", forType: .string)
        ClipboardOutput.clearIfOurs()  // should not clear since state was reset

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Something else")
    }
}
