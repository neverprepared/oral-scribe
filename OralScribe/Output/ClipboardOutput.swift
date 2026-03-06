import AppKit

// MARK: - Clipboard Output

struct ClipboardOutput {
    private static var lastWrittenText: String?

    static func write(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        lastWrittenText = text
    }

    /// Clears the clipboard only if it still contains the text we last wrote.
    static func clearIfOurs() {
        guard let last = lastWrittenText,
              NSPasteboard.general.string(forType: .string) == last else {
            lastWrittenText = nil
            return
        }
        NSPasteboard.general.clearContents()
        lastWrittenText = nil
    }
}
