import Foundation
import AppKit

// MARK: - Notes Output

struct NotesOutput {
    /// Appends text to Apple Notes via AppleScript
    static func appendToNotes(_ text: String) async throws {
        let script = """
        tell application "Notes"
            activate
            set newNote to make new note at folder "Notes" of default account
            set body of newNote to "\(text.escaped)"
        end tell
        """

        guard let appleScript = NSAppleScript(source: script) else {
            throw NotesOutputError.scriptCreationFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var errorDict: NSDictionary?
                appleScript.executeAndReturnError(&errorDict)

                if let error = errorDict {
                    let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                    continuation.resume(throwing: NotesOutputError.scriptExecutionFailed(message))
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

// MARK: - File Output

struct FileOutput {
    static func append(_ text: String, to filePath: String) throws {
        let url = URL(fileURLWithPath: filePath)
        let line = "\(text)\n"

        if FileManager.default.fileExists(atPath: filePath) {
            let fileHandle = try FileHandle(forWritingTo: url)
            fileHandle.seekToEndOfFile()
            if let data = line.data(using: .utf8) {
                fileHandle.write(data)
            }
            fileHandle.closeFile()
        } else {
            try line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Errors

enum NotesOutputError: LocalizedError {
    case scriptCreationFailed
    case scriptExecutionFailed(String)

    var errorDescription: String? {
        switch self {
        case .scriptCreationFailed: return "Failed to create AppleScript"
        case .scriptExecutionFailed(let msg): return "AppleScript error: \(msg)"
        }
    }
}

// MARK: - String Escaping for AppleScript

private extension String {
    var escaped: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
