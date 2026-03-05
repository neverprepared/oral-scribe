import Foundation
import AVFoundation

// MARK: - Transcription Result

struct TranscriptionResult {
    let text: String
    let confidence: Float?
    let duration: TimeInterval?
    let backend: TranscriptionBackend
}

// MARK: - Transcription Errors

enum TranscriptionError: LocalizedError {
    case notAvailable
    case notAuthorized
    case noResult
    case apiError(String)
    case networkError(Error)
    case fileError(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable: return "Speech recognition is not available"
        case .notAuthorized: return "Speech recognition is not authorized"
        case .noResult: return "No transcription result"
        case .apiError(let msg): return "API error: \(msg)"
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        case .fileError(let msg): return "File error: \(msg)"
        }
    }
}

// MARK: - Protocol

protocol TranscriptionEngine: AnyObject {
    /// Live transcription via audio buffers (Apple Speech)
    func transcribeLive(recorder: AudioRecorder) async throws -> AsyncThrowingStream<String, Error>

    /// File-based transcription (Whisper API, WhisperKit)
    func transcribeFile(at fileURL: URL) async throws -> TranscriptionResult
}
