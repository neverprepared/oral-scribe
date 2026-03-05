import Foundation
import WhisperKit

// MARK: - WhisperKit Engine

class WhisperKitEngine: TranscriptionEngine {
    private let pipe: WhisperKit

    init(pipe: WhisperKit) {
        self.pipe = pipe
    }

    // WhisperKit is file-based only — live streaming not supported
    func transcribeLive(recorder: AudioRecorder) async throws -> AsyncThrowingStream<String, Error> {
        throw TranscriptionError.notAvailable
    }

    func transcribeFile(at fileURL: URL) async throws -> TranscriptionResult {
        let segments = try await pipe.transcribe(audioPath: fileURL.path)
        guard !segments.isEmpty else {
            throw TranscriptionError.noResult
        }

        let text = segments
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)

        return TranscriptionResult(
            text: text,
            confidence: nil,
            duration: nil,
            backend: .whisperKit
        )
    }
}
