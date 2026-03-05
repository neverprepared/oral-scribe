import Foundation

// MARK: - LLM Processor Protocol

protocol LLMProcessor: AnyObject {
    func process(text: String, mode: ProcessingMode, customPrompt: String?) async throws -> String
}

// MARK: - LLM Errors

enum LLMError: LocalizedError {
    case notAvailable
    case apiError(String)
    case networkError(Error)
    case noResponse

    var errorDescription: String? {
        switch self {
        case .notAvailable: return "LLM processor is not available"
        case .apiError(let msg): return "LLM API error: \(msg)"
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        case .noResponse: return "No response from LLM"
        }
    }
}
