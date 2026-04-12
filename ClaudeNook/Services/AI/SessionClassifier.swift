//
//  SessionClassifier.swift
//  ClaudeNook
//
//  Periodically classifies active Claude Code sessions using a local LLM.
//  Produces SessionClassification (summary, category, progress) from recent chat activity.
//  Degrades gracefully when no LLM backend is available.
//

import ClaudeNookShared
import Foundation
import os

/// Actor that periodically classifies active sessions via a local LLM
actor SessionClassifier {
    static let shared = SessionClassifier()

    private static let logger = Logger(subsystem: "com.claudenook", category: "SessionClassifier")

    private var backend: (any LLMBackend)?
    private var classificationTask: Task<Void, Never>?
    private var intervalSeconds: UInt64 = 30

    /// Track how many chat items we last classified for each session (debounce)
    private var lastClassifiedItemCount: [String: Int] = [:]
    /// Minimum change in chat items before re-classifying
    private let minItemDelta = 3

    // MARK: - Lifecycle

    func start(backend: any LLMBackend, intervalSeconds: UInt64 = 30) {
        self.backend = backend
        self.intervalSeconds = intervalSeconds
        stop()

        classificationTask = Task { [weak self] in
            // Initial delay before first classification
            try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)

            while !Task.isCancelled {
                guard let self = self else { return }
                await self.classifyActiveSessions()
                try? await Task.sleep(nanoseconds: self.intervalSeconds * 1_000_000_000)
            }
        }

        Self.logger.info("Started with interval \(intervalSeconds)s")
    }

    func stop() {
        classificationTask?.cancel()
        classificationTask = nil
        Self.logger.info("Stopped")
    }

    // MARK: - Classification Loop

    private func classifyActiveSessions() async {
        guard let backend = backend else { return }

        // Check backend availability (cached for this cycle)
        guard await backend.isAvailable() else {
            Self.logger.debug("Backend not available, skipping cycle")
            return
        }

        // Get current sessions from SessionStore
        let sessions = await SessionStore.shared.allSessions()

        // Only classify active sessions with enough context
        let candidates = sessions.filter { session in
            let isActive: Bool
            switch session.phase {
            case .processing, .waitingForApproval, .waitingForInput, .compacting:
                isActive = true
            default:
                isActive = false
            }

            guard isActive else { return false }
            guard session.chatItems.count >= 2 else { return false }

            // Debounce: skip if not enough new activity since last classification
            let lastCount = lastClassifiedItemCount[session.sessionId] ?? 0
            return session.chatItems.count - lastCount >= minItemDelta || session.classification == nil
        }

        // Limit to 3 sessions per cycle to avoid overloading
        for session in candidates.prefix(3) {
            if let classification = await classifySession(session) {
                lastClassifiedItemCount[session.sessionId] = session.chatItems.count
                await SessionStore.shared.process(
                    .classificationUpdated(sessionId: session.sessionId, classification: classification)
                )
            }
        }
    }

    // MARK: - Single Session Classification

    private func classifySession(_ session: SessionState) async -> SessionClassification? {
        guard let backend = backend else { return nil }

        let prompt = buildPrompt(for: session)

        do {
            let response = try await backend.generate(prompt: prompt)
            return parseResponse(response)
        } catch {
            Self.logger.debug("Classification failed for \(session.sessionId.prefix(8)): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Prompt Building

    private func buildPrompt(for session: SessionState) -> String {
        let recentItems = session.chatItems.suffix(5)

        var activityLines: [String] = []
        for item in recentItems {
            switch item.type {
            case .user(let text):
                let truncated = String(text.prefix(80))
                activityLines.append("User: \"\(truncated)\"")
            case .assistant(let text):
                let truncated = String(text.prefix(80))
                activityLines.append("Assistant: \"\(truncated)\"")
            case .toolCall(let toolItem):
                let preview = toolItem.inputPreview
                let input = preview.isEmpty ? "" : " \(preview)"
                activityLines.append("Tool: \(toolItem.name)\(input)")
            case .thinking:
                continue
            case .interrupted:
                activityLines.append("[interrupted]")
            }
        }

        let activity = activityLines.joined(separator: "\n")

        return """
        You classify Claude Code CLI sessions. Given recent activity, produce a JSON classification.

        Valid categories: coding, debugging, research, refactoring, testing, deploying, configuring, reviewing, planning, other
        Valid progress values: starting, inProgress, wrappingUp, blocked, waiting

        Example:
        User: "Fix the login bug where users get 403 after password reset"
        Tool: Read src/auth/login.ts
        Tool: Edit src/auth/login.ts

        {"summary":"Fixing 403 error after password reset","category":"debugging","progress":"inProgress"}

        Now classify:
        Project: \(session.projectName)
        Phase: \(session.phase.rawValue)
        \(activity)

        Respond with ONLY a JSON object:
        """
    }

    // MARK: - Response Parsing (3-tier fallback)

    func parseResponse(_ response: String) -> SessionClassification? {
        // Tier 1: Direct JSON decode
        if let data = response.data(using: .utf8),
           let raw = try? JSONDecoder().decode(RawClassification.self, from: data) {
            return raw.toClassification()
        }

        // Tier 2: Extract JSON object from surrounding text (handles markdown code blocks)
        if let jsonString = extractJSON(from: response),
           let data = jsonString.data(using: .utf8),
           let raw = try? JSONDecoder().decode(RawClassification.self, from: data) {
            return raw.toClassification()
        }

        // Tier 3: Regex extraction of individual fields
        let summary = extractField(from: response, field: "summary")
        let categoryStr = extractField(from: response, field: "category")
        let progressStr = extractField(from: response, field: "progress")

        if let summary = summary {
            return SessionClassification(
                summary: String(summary.prefix(100)),
                category: categoryStr.flatMap { SessionCategory(rawValue: $0) } ?? .other,
                progress: progressStr.flatMap { normalizeProgress($0) } ?? .waiting
            )
        }

        Self.logger.debug("Failed to parse classification response: \(response.prefix(200))")
        return nil
    }

    /// Extract a JSON object from text that may contain markdown or other wrapping
    private func extractJSON(from text: String) -> String? {
        // Find the first { and matching }
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var end: String.Index?
        for i in text.indices[start...] {
            if text[i] == "{" { depth += 1 }
            if text[i] == "}" {
                depth -= 1
                if depth == 0 {
                    end = i
                    break
                }
            }
        }
        guard let endIndex = end else { return nil }
        return String(text[start...endIndex])
    }

    /// Extract a string field value from JSON-like text
    private func extractField(from text: String, field: String) -> String? {
        // Match "field": "value" or "field":"value"
        let pattern = "\"\(field)\"\\s*:\\s*\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    /// Normalize progress values (models may output "in_progress" or "in-progress" instead of "inProgress")
    private func normalizeProgress(_ value: String) -> SessionProgress? {
        if let direct = SessionProgress(rawValue: value) {
            return direct
        }
        // Handle common variations
        switch value.lowercased().replacingOccurrences(of: "[_-]", with: "", options: .regularExpression) {
        case "inprogress": return .inProgress
        case "wrappingup": return .wrappingUp
        case "starting": return .starting
        case "blocked": return .blocked
        case "waiting": return .waiting
        default: return nil
        }
    }
}

// MARK: - Raw JSON Decoding

/// Intermediate struct for lenient JSON decoding from LLM output
@preconcurrency
private struct RawClassification: Decodable, Sendable {
    let summary: String
    let category: String
    let progress: String

    nonisolated func toClassification() -> SessionClassification? {
        let cat = SessionCategory(rawValue: category) ?? .other
        let progressValue: SessionProgress
        if let direct = SessionProgress(rawValue: progress) {
            progressValue = direct
        } else {
            // Normalize common variations
            switch progress.lowercased().replacingOccurrences(of: "[_-]", with: "", options: .regularExpression) {
            case "inprogress": progressValue = .inProgress
            case "wrappingup": progressValue = .wrappingUp
            default: progressValue = .waiting
            }
        }

        return SessionClassification(
            summary: String(summary.prefix(100)),
            category: cat,
            progress: progressValue
        )
    }
}
