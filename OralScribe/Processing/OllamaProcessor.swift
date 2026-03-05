import Foundation

// MARK: - Ollama Processor

class OllamaProcessor: LLMProcessor {
    var host: String
    var model: String

    init(host: String = "http://localhost:11434", model: String = "llama3.2") {
        self.host = host
        self.model = model
    }

    func process(text: String, mode: ProcessingMode, customPrompt: String?) async throws -> String {
        guard mode != .passthrough else { return text }

        let host = self.host
        let model = self.model

        guard let url = URL(string: "\(host)/api/generate") else {
            throw LLMError.apiError("Invalid Ollama host URL")
        }

        let systemPrompt: String
        if mode == .custom, let custom = customPrompt, !custom.isEmpty {
            systemPrompt = custom
        } else if let defaultPrompt = mode.defaultPrompt {
            systemPrompt = defaultPrompt
        } else {
            return text
        }

        let payload: [String: Any] = [
            "model": model,
            "prompt": "\(systemPrompt)\n\nText: \(text)",
            "stream": false
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw LLMError.apiError("HTTP \(httpResponse.statusCode): \(errorText)")
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let responseText = json["response"] as? String else {
                throw LLMError.noResponse
            }

            return responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as LLMError {
            throw error
        } catch {
            throw LLMError.networkError(error)
        }
    }
}
