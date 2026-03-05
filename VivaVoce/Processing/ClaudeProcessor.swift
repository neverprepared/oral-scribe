import Foundation

// MARK: - Claude Processor (Future Stub)

/// Placeholder for Anthropic Claude API integration
class ClaudeProcessor: LLMProcessor {
    func process(text: String, mode: ProcessingMode, customPrompt: String?) async throws -> String {
        throw LLMError.notAvailable
    }
}
