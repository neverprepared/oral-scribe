import Foundation

// MARK: - Translation Manager

@MainActor
class TranslationManager {
    static let shared = TranslationManager()

    private init() {}

    func translate(text: String, targetLanguage: String) async throws -> String {
        if #available(macOS 15.0, *) {
            return try await translateWithFramework(text: text, targetLanguage: targetLanguage)
        } else {
            throw TranslationError.notAvailable
        }
    }

    @available(macOS 15.0, *)
    private func translateWithFramework(text: String, targetLanguage: String) async throws -> String {
        // Translation framework is available but requires specific entitlements
        // and may need UI-level session approval
        // For now, return a stub — full integration requires Translation.framework session setup
        // which needs to be done at the View level with TranslationSession
        throw TranslationError.notAvailable
    }
}

// MARK: - Translation Errors

enum TranslationError: LocalizedError {
    case notAvailable
    case translationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable: return "Translation requires macOS 15 or later"
        case .translationFailed(let msg): return "Translation failed: \(msg)"
        }
    }
}
