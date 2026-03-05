import Foundation
import AVFoundation
import SwiftWhisper

// MARK: - SwiftWhisper Engine

class SwiftWhisperEngine: TranscriptionEngine {
    private let whisper: Whisper

    init(whisper: Whisper) {
        self.whisper = whisper
    }

    func transcribeLive(recorder: AudioRecorder) async throws -> AsyncThrowingStream<String, Error> {
        throw TranscriptionError.notAvailable
    }

    func transcribeFile(at fileURL: URL) async throws -> TranscriptionResult {
        var frames = try extractPCMFrames(from: fileURL)
        guard !frames.isEmpty else { throw TranscriptionError.noResult }

        // Pad to at least 1 second so whisper.cpp's mel computation has enough frames.
        // 30-second padding is only needed for language auto-detection, which we disable.
        let minFrames = 16000
        if frames.count < minFrames {
            frames.append(contentsOf: [Float](repeating: 0, count: minFrames - frames.count))
        }

        let segments = try await whisper.transcribe(audioFrames: frames)
        guard !segments.isEmpty else { throw TranscriptionError.noResult }

        let raw = segments
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)

        // Strip Whisper hallucination tokens like [BLANK_AUDIO], [silence], [noise], [music]
        let stripped = raw
            .replacingOccurrences(of: "\\[.*?\\]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let text = Self.removeTrailingHallucinations(stripped)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { throw TranscriptionError.noResult }

        return TranscriptionResult(
            text: text,
            confidence: nil,
            duration: nil,
            backend: .whisperCpp
        )
    }

    // MARK: - Hallucination Filter

    // Whisper is trained on YouTube/podcast audio that ends with common sign-offs.
    // Strip these phrases when they appear as trailing sentences in the output.
    private static let trailingHallucinationPatterns: [String] = [
        "thank you for watching",
        "thanks for watching",
        "thank you for listening",
        "thanks for listening",
        "please subscribe",
        "don't forget to subscribe",
        "like and subscribe",
        "see you next time",
        "all rights reserved",
        "transcribed by",
        "subtitles by",
        "captions by",
        "thank you very much",
        "thank you so much",
        "thank you\\.?$",
        "thanks\\.?$",
        "let's go",
        "let's go\\!?$",
    ]

    private static func removeTrailingHallucinations(_ text: String) -> String {
        // Split into sentences, remove trailing ones that are pure hallucinations
        var sentences = text.components(separatedBy: .init(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        while let last = sentences.last {
            let lower = last.lowercased()
            let isHallucination = trailingHallucinationPatterns.contains { pattern in
                lower == pattern.replacingOccurrences(of: "\\.\\?\\$", with: "", options: .regularExpression)
                    || lower.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
            }
            if isHallucination {
                sentences.removeLast()
            } else {
                break
            }
        }

        return sentences.joined(separator: ". ")
    }

    // MARK: - PCM Extraction

    // Reads the WAV file and returns 16kHz mono float32 PCM frames,
    // which is exactly what whisper.cpp expects.
    private func extractPCMFrames(from fileURL: URL) throws -> [Float] {
        let audioFile = try AVAudioFile(forReading: fileURL)
        let frameCount = AVAudioFrameCount(audioFile.length)
        guard frameCount > 0 else { throw TranscriptionError.noResult }

        // processingFormat is always float32 non-interleaved
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: audioFile.processingFormat,
            frameCapacity: frameCount
        ) else { throw TranscriptionError.noResult }

        try audioFile.read(into: buffer)

        // Our WAV files are already 16kHz mono — extract directly
        guard let channelData = buffer.floatChannelData?[0] else {
            throw TranscriptionError.noResult
        }
        return Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
    }
}
