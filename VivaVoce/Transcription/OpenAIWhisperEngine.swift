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
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        guard let audioData = try? Data(contentsOf: fileURL) else {
            throw TranscriptionError.fileError("Cannot read audio file")
        }

        var body = Data()
        body.appendMultipart(boundary: boundary, name: "model", value: model)
        body.appendMultipart(boundary: boundary, name: "response_format", value: "text")
        body.appendMultipartFile(
            boundary: boundary,
            name: "file",
            filename: "audio.wav",
            mimeType: "audio/wav",
            data: audioData
        )
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

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

    mutating func appendMultipartFile(boundary: String, name: String, filename: String, mimeType: String, data fileData: Data) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(fileData)
        append("\r\n".data(using: .utf8)!)
    }
}
