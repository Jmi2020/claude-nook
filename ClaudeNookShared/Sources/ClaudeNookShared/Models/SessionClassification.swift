//
//  SessionClassification.swift
//  ClaudeNookShared
//
//  AI-generated classification of what a Claude Code session is doing.
//  Produced by local LLM (Ollama/LM Studio) on the macOS side,
//  transmitted to iOS via the existing session update protocol.
//

import Foundation

/// What kind of work a session is doing
public enum SessionCategory: String, Codable, Sendable, CaseIterable {
    case coding
    case debugging
    case research
    case refactoring
    case testing
    case deploying
    case configuring
    case reviewing
    case planning
    case other
}

/// How far along the session is in its current task
public enum SessionProgress: String, Codable, Sendable, CaseIterable {
    case starting
    case inProgress
    case wrappingUp
    case blocked
    case waiting
}

/// AI classification of a Claude Code session's activity
public struct SessionClassification: Codable, Sendable, Equatable {
    /// Human-readable summary of what Claude is doing (e.g., "Refactoring authentication module")
    public let summary: String
    /// Category of work being performed
    public let category: SessionCategory
    /// Progress through the current task
    public let progress: SessionProgress
    /// When this classification was generated
    public let classifiedAt: Date

    public init(
        summary: String,
        category: SessionCategory,
        progress: SessionProgress,
        classifiedAt: Date = Date()
    ) {
        self.summary = summary
        self.category = category
        self.progress = progress
        self.classifiedAt = classifiedAt
    }
}
