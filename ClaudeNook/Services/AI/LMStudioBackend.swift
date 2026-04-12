//
//  LMStudioBackend.swift
//  ClaudeNook
//
//  LM Studio / OpenAI-compatible API client for local LLM inference.
//  Also works with LM Link (Tailscale-based) for cross-device model access.
//

import Foundation

/// LM Studio backend using the OpenAI-compatible /v1/chat/completions endpoint
struct LMStudioBackend: LLMBackend, Sendable {
    let model: String
    let endpoint: URL
    let timeoutSeconds: TimeInterval

    init(
        model: String = "gemma4:e4b",
        endpoint: String = "http://localhost:1234",
        timeoutSeconds: TimeInterval = 15
    ) {
        self.model = model
        self.endpoint = URL(string: endpoint)!
        self.timeoutSeconds = timeoutSeconds
    }

    func generate(prompt: String) async throws -> String {
        let url = endpoint.appendingPathComponent("v1/chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeoutSeconds

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3,
            "max_tokens": 150
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw LLMError.requestFailed("HTTP \(statusCode)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.invalidResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func isAvailable() async -> Bool {
        let url = endpoint.appendingPathComponent("v1/models")
        var request = URLRequest(url: url)
        request.timeoutInterval = 3

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
