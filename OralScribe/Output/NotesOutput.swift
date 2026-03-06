import Foundation
import AppKit

// MARK: - Notes Output

struct NotesOutput {
    /// Appends text to Apple Notes via AppleScript.
    /// Uses a temp file to pass the transcript, eliminating AppleScript injection surface.
    static func appendToNotes(_ text: String) async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".txt")

        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            try text.write(to: tempURL, atomically: true, encoding: .utf8)
        } catch {
            throw NotesOutputError.scriptCreationFailed
        }

        let tempPath = tempURL.path
        let script = """
        tell application "Notes"
            activate
            set noteText to read POSIX file "\(tempPath)" as «class utf8»
            set newNote to make new note at folder "Notes" of default account
            set body of newNote to noteText
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
        let expandedPath = (filePath as NSString).expandingTildeInPath
        let resolvedPath = (expandedPath as NSString).resolvingSymlinksInPath
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

        guard expandedPath.hasPrefix(homeDir), resolvedPath.hasPrefix(homeDir) else {
            throw FileOutputError.pathOutsideHomeDirectory
        }

        let url = URL(fileURLWithPath: expandedPath)
        let line = "\(text)\n"

        if FileManager.default.fileExists(atPath: expandedPath) {
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

enum FileOutputError: LocalizedError {
    case pathOutsideHomeDirectory

    var errorDescription: String? {
        switch self {
        case .pathOutsideHomeDirectory: return "Output file path must be within your home directory"
        }
    }
}
