//
//  OllamaBackend.swift
//  ClaudeNook
//
//  Ollama HTTP API client for local LLM inference.
//  Calls /api/generate with non-streaming mode.
//

import Foundation

/// Ollama backend using the native /api/generate endpoint
struct OllamaBackend: LLMBackend, Sendable {
    let model: String
    let endpoint: URL
    let timeoutSeconds: TimeInterval

    init(
        model: String = "gemma4:e4b",
        endpoint: String = "http://localhost:11434",
        timeoutSeconds: TimeInterval = 15
    ) {
        self.model = model
        self.endpoint = URL(string: endpoint)!
        self.timeoutSeconds = timeoutSeconds
    }

    func generate(prompt: String) async throws -> String {
        let url = endpoint.appendingPathComponent("api/generate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeoutSeconds

        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "options": [
                "temperature": 0.3,
                "num_predict": 150
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw LLMError.requestFailed("HTTP \(statusCode)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseText = json["response"] as? String else {
            throw LLMError.invalidResponse
        }

        return responseText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func isAvailable() async -> Bool {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 3

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
