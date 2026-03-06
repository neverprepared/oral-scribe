import Foundation
import Speech
import AVFoundation

// MARK: - Apple Speech Engine

class AppleSpeechEngine: TranscriptionEngine {
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private let onDevice: Bool

    init(locale: String = "en-US", onDevice: Bool = true) {
        self.onDevice = onDevice
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale))
    }

    // MARK: - Live Transcription

    func transcribeLive(recorder: AudioRecorder) async throws -> AsyncThrowingStream<String, Error> {
        guard let recognizer, recognizer.isAvailable else {
            throw TranscriptionError.notAvailable
        }

        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw TranscriptionError.notAuthorized
        }

        return AsyncThrowingStream { continuation in
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = self.onDevice
            self.recognitionRequest = request

            self.recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    // Only propagate if it's not a cancellation
                    let nsError = error as NSError
                    if nsError.code != 301 { // 301 = cancelled
                        continuation.finish(throwing: error)
                    } else {
                        continuation.finish()
                    }
                    return
                }

                if let result {
                    continuation.yield(result.bestTranscription.formattedString)
                    if result.isFinal {
                        continuation.finish()
                    }
                }
            }

            Task { @MainActor in
                try recorder.startRecording { buffer, _ in
                    request.append(buffer)
                }
            }
        }
    }

    /// Restart the recognition task without stopping the audio recorder's tap.
    /// Ends the current request/task and creates a fresh one. The caller must
    /// re-iterate the returned stream.
    func restartRecognition(recorder: AudioRecorder) -> AsyncThrowingStream<String, Error> {
        // End the current recognition cleanly
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil

        guard let recognizer, recognizer.isAvailable else {
            return AsyncThrowingStream { $0.finish(throwing: TranscriptionError.notAvailable) }
        }

        return AsyncThrowingStream { continuation in
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = self.onDevice
            self.recognitionRequest = request

            self.recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    let nsError = error as NSError
                    if nsError.code != 301 {
                        continuation.finish(throwing: error)
                    } else {
                        continuation.finish()
                    }
                    return
                }

                if let result {
                    continuation.yield(result.bestTranscription.formattedString)
                    if result.isFinal {
                        continuation.finish()
                    }
                }
            }

            // Re-route the existing audio tap's buffers to the new request.
            // The recorder's tap is still installed — we just swap the callback target.
            Task { @MainActor in
                recorder.setBufferCallback { buffer, _ in
                    request.append(buffer)
                }
            }
        }
    }

    func stopLiveTranscription() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }

    // MARK: - File Transcription (not primary use case for Apple Speech)

    func transcribeFile(at fileURL: URL) async throws -> TranscriptionResult {
        guard let recognizer, recognizer.isAvailable else {
            throw TranscriptionError.notAvailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: fileURL)
            request.shouldReportPartialResults = false

            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let result, result.isFinal else { return }
                continuation.resume(returning: TranscriptionResult(
                    text: result.bestTranscription.formattedString,
                    confidence: result.bestTranscription.segments.first?.confidence,
                    duration: nil,
                    backend: .appleSpeech
                ))
            }
        }
    }
}
