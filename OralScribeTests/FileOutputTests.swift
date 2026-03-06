import XCTest
@testable import OralScribe

final class FileOutputTests: XCTestCase {

    private var tempPaths: [String] = []

    override func tearDown() {
        tempPaths.forEach { try? FileManager.default.removeItem(atPath: $0) }
        tempPaths = []
        super.tearDown()
    }

    // MARK: - Path Validation

    func testValidHomeDirectoryPathSucceeds() throws {
        let path = tempPath(in: "Library/Application Support")
        XCTAssertNoThrow(try FileOutput.append("test", to: path))
    }

    func testTildePathExpandsAndSucceeds() throws {
        let fileName = "oralscribe_test_\(UUID().uuidString).txt"
        let tildePath = "~/\(fileName)"
        let expandedPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(fileName).path
        tempPaths.append(expandedPath)

        XCTAssertNoThrow(try FileOutput.append("tilde test", to: tildePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: expandedPath))
    }

    func testEtcHostsThrows() {
        XCTAssertThrowsError(try FileOutput.append("bad", to: "/etc/hosts")) { error in
            XCTAssertEqual(error as? FileOutputError, .pathOutsideHomeDirectory)
        }
    }

    func testTmpPathThrows() {
        XCTAssertThrowsError(try FileOutput.append("bad", to: "/tmp/evil.txt")) { error in
            XCTAssertEqual(error as? FileOutputError, .pathOutsideHomeDirectory)
        }
    }

    func testRootPathThrows() {
        XCTAssertThrowsError(try FileOutput.append("bad", to: "/output.txt")) { error in
            XCTAssertEqual(error as? FileOutputError, .pathOutsideHomeDirectory)
        }
    }

    func testVarFoldersPathThrows() {
        XCTAssertThrowsError(try FileOutput.append("bad", to: "/var/folders/test.txt")) { error in
            XCTAssertEqual(error as? FileOutputError, .pathOutsideHomeDirectory)
        }
    }

    // MARK: - File Creation

    func testCreatesNewFile() throws {
        let path = tempPath(in: "Library/Application Support")
        try FileOutput.append("First line", to: path)
        let content = try String(contentsOfFile: path)
        XCTAssertEqual(content, "First line\n")
    }

    func testCreatedFileHasNewlineTerminator() throws {
        let path = tempPath(in: "Library/Application Support")
        try FileOutput.append("Hello", to: path)
        let content = try String(contentsOfFile: path)
        XCTAssertTrue(content.hasSuffix("\n"))
    }

    // MARK: - Append

    func testAppendsToExistingFile() throws {
        let path = tempPath(in: "Library/Application Support")
        try FileOutput.append("First line", to: path)
        try FileOutput.append("Second line", to: path)
        let content = try String(contentsOfFile: path)
        XCTAssertEqual(content, "First line\nSecond line\n")
    }

    func testAppendThreeLines() throws {
        let path = tempPath(in: "Library/Application Support")
        try FileOutput.append("Line 1", to: path)
        try FileOutput.append("Line 2", to: path)
        try FileOutput.append("Line 3", to: path)
        let content = try String(contentsOfFile: path)
        XCTAssertEqual(content, "Line 1\nLine 2\nLine 3\n")
    }

    func testAppendsUnicodeContent() throws {
        let path = tempPath(in: "Library/Application Support")
        try FileOutput.append("Hello 🌍 Привет", to: path)
        let content = try String(contentsOfFile: path)
        XCTAssertEqual(content, "Hello 🌍 Привет\n")
    }

    func testAppendsEmptyString() throws {
        let path = tempPath(in: "Library/Application Support")
        try FileOutput.append("", to: path)
        let content = try String(contentsOfFile: path)
        XCTAssertEqual(content, "\n")
    }

    // MARK: - Helpers

    private func tempPath(in subdirectory: String) -> String {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(subdirectory)
            .appendingPathComponent("oralscribe_test_\(UUID().uuidString).txt")
            .path
        tempPaths.append(path)
        return path
    }
}

extension FileOutputError: Equatable {
    public static func == (lhs: FileOutputError, rhs: FileOutputError) -> Bool {
        switch (lhs, rhs) {
        case (.pathOutsideHomeDirectory, .pathOutsideHomeDirectory): return true
        }
    }
}
