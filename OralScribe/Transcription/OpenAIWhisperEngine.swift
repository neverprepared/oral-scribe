import Foundation

// MARK: - OpenAI Whisper Engine

class OpenAIWhisperEngine: TranscriptionEngine {
    var apiKey: String
    var model: String
    var translateMode: Bool

    init(apiKey: String = "", model: String = "whisper-1", translateMode: Bool = false) {
        self.apiKey = apiKey
        self.model = model
        self.translateMode = translateMode
    }

    // MARK: - Live (not supported — delegates to file)

    func transcribeLive(recorder: AudioRecorder) async throws -> AsyncThrowingStream<String, Error> {
        // Whisper is file-based; live isn't supported
        throw TranscriptionError.notAvailable
    }

    // MARK: - File Transcription

    func transcribeFile(at fileURL: URL) async throws -> TranscriptionResult {
        let apiKey = self.apiKey
        guard !apiKey.isEmpty else {
            throw TranscriptionError.apiError("OpenAI API key not configured")
        }

        let model = self.model
        let translateMode = self.translateMode
        let endpoint = translateMode
            ? "https://api.openai.com/v1/audio/translations"
            : "https://api.openai.com/v1/audio/transcriptions"

        guard let url = URL(string: endpoint) else {
            throw TranscriptionError.apiError("Invalid endpoint URL")
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Write multipart body to a temp file so URLSession streams the audio
        // rather than loading it entirely into memory.
        let bodyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("oralscribe_upload_\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: bodyURL) }

        var preamble = Data()
        preamble.appendMultipart(boundary: boundary, name: "model", value: model)
        preamble.appendMultipart(boundary: boundary, name: "response_format", value: "text")
        preamble.append("--\(boundary)\r\n".data(using: .utf8)!)
        preamble.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        preamble.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)

        try preamble.write(to: bodyURL)

        let bodyHandle = try FileHandle(forWritingTo: bodyURL)
        bodyHandle.seekToEndOfFile()
        let audioHandle = try FileHandle(forReadingFrom: fileURL)
        while true {
            let chunk = audioHandle.readData(ofLength: 65536)
            if chunk.isEmpty { break }
            bodyHandle.write(chunk)
        }
        audioHandle.closeFile()
        bodyHandle.write("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        bodyHandle.closeFile()

        do {
            let (data, response) = try await URLSession.shared.upload(for: request, fromFile: bodyURL)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw TranscriptionError.apiError("HTTP \(httpResponse.statusCode): \(errorText)")
            }

            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.isEmpty {
                throw TranscriptionError.noResult
            }

            return TranscriptionResult(text: text, confidence: nil, duration: nil, backend: .openAIWhisper)
        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError.networkError(error)
        }
    }
}

// MARK: - Multipart Helpers

private extension Data {
    mutating func appendMultipart(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }
}
