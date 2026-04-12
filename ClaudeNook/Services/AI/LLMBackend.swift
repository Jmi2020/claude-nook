//
//  LLMBackend.swift
//  ClaudeNook
//
//  Protocol for local LLM backends used for session classification.
//  Supports Ollama and LM Studio (OpenAI-compatible) endpoints.
//

import Foundation

/// Errors from LLM backend operations
enum LLMError: Error, LocalizedError {
    case notAvailable
    case requestFailed(String)
    case invalidResponse
    case timeout

    var errorDescription: String? {
        switch self {
        case .notAvailable: return "LLM backend is not running"
        case .requestFailed(let msg): return "LLM request failed: \(msg)"
        case .invalidResponse: return "Invalid response from LLM"
        case .timeout: return "LLM request timed out"
        }
    }
}

/// Protocol for local LLM inference backends
protocol LLMBackend: Sendable {
    /// Generate a completion for the given prompt
    func generate(prompt: String) async throws -> String

    /// Check if the backend is running and available
    func isAvailable() async -> Bool
}
