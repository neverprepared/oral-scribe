import Foundation
import AppKit

// MARK: - Output Manager

@MainActor
class OutputManager {
    static let shared = OutputManager()

    private init() {}

    func deliver(_ text: String, settings: SettingsManager, targetApp: NSRunningApplication?) async {
        // Clipboard always first so it's ready before any paste
        if settings.outputToClipboard {
            ClipboardOutput.write(text)
        }

        // Active field injection — sends directly to the target process, no focus change needed
        if settings.outputToActiveField {
            AccessibilityOutput.inject(text, into: targetApp)
        }

        // Apple Notes
        if settings.outputToAppleNotes {
            do {
                try await NotesOutput.appendToNotes(text)
            } catch {
                print("Notes output failed: \(error.localizedDescription)")
            }
        }

        // File
        if settings.outputToFile && !settings.outputFilePath.isEmpty {
            do {
                try FileOutput.append(text, to: settings.outputFilePath)
            } catch {
                print("File output failed: \(error.localizedDescription)")
            }
        }
    }
}
