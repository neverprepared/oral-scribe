import Foundation

// MARK: - Ollama Processor

class OllamaProcessor: LLMProcessor {
    var host: String
    var model: String

    init(host: String = "http://localhost:11434", model: String = "llama3.2") {
        self.host = host
        self.model = model

        if let url = URL(string: host), let hostname = url.host {
            let localHosts = ["localhost", "127.0.0.1", "::1"]
            if !localHosts.contains(hostname) {
                print("OralScribe: Ollama host '\(hostname)' is not localhost — transcripts will be sent to this remote host.")
            }
        }
    }

    /// Fetch the list of locally installed model names from the Ollama API.
    func fetchModels() async -> [String] {
        guard let url = URL(string: "\(host)/api/tags") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else { return [] }
            return models.compactMap { $0["name"] as? String }.sorted()
        } catch {
            return []
        }
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
            "system": systemPrompt,
            "prompt": text,
            "stream": false
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
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

            return stripPreamble(responseText.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch let error as LLMError {
            throw error
        } catch {
            throw LLMError.networkError(error)
        }
    }

    /// Strip common LLM preamble from the response as a safety net.
    private func stripPreamble(_ text: String) -> String {
        let lowered = text.lowercased()
        // Match "Here is/Here's the <anything>:" on the first line
        if let colonRange = lowered.range(of: ":"),
           lowered[lowered.startIndex..<colonRange.lowerBound].hasPrefix("here") {
            let after = String(text[colonRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return after.isEmpty ? text : after
        }
        return text
    }
}
