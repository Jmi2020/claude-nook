//
//  ToolStatus.swift
//  ClaudeNookShared
//
//  Status tracking for tool execution.
//

import Foundation

/// Status of a tool's execution
public enum ToolStatus: String, Sendable, Codable, CustomStringConvertible {
    case running
    case waitingForApproval
    case success
    case error
    case interrupted

    public nonisolated var description: String {
        switch self {
        case .running: return "running"
        case .waitingForApproval: return "waitingForApproval"
        case .success: return "success"
        case .error: return "error"
        case .interrupted: return "interrupted"
        }
    }
}

// Explicit nonisolated Equatable conformance to avoid actor isolation issues
extension ToolStatus: Equatable {
    public nonisolated static func == (lhs: ToolStatus, rhs: ToolStatus) -> Bool {
        switch (lhs, rhs) {
        case (.running, .running): return true
        case (.waitingForApproval, .waitingForApproval): return true
        case (.success, .success): return true
        case (.error, .error): return true
        case (.interrupted, .interrupted): return true
        default: return false
        }
    }
}

/// Represents a tool call made by a subagent (Task tool)
public struct SubagentToolCall: Equatable, Identifiable, Sendable, Codable {
    public let id: String
    public let name: String
    public let input: [String: String]
    public var status: ToolStatus
    public let timestamp: Date

    public init(id: String, name: String, input: [String: String], status: ToolStatus, timestamp: Date) {
        self.id = id
        self.name = name
        self.input = input
        self.status = status
        self.timestamp = timestamp
    }

    /// Short description for display
    public var displayText: String {
        switch name {
        case "Read":
            if let path = input["file_path"] {
                return URL(fileURLWithPath: path).lastPathComponent
            }
            return "Reading..."
        case "Grep":
            if let pattern = input["pattern"] {
                return "grep: \(pattern)"
            }
            return "Searching..."
        case "Glob":
            if let pattern = input["pattern"] {
                return "glob: \(pattern)"
            }
            return "Finding files..."
        case "Bash":
            if let desc = input["description"] {
                return desc
            }
            if let cmd = input["command"] {
                let firstLine = cmd.components(separatedBy: "\n").first ?? cmd
                return String(firstLine.prefix(40))
            }
            return "Running command..."
        case "Edit":
            if let path = input["file_path"] {
                return "Edit: \(URL(fileURLWithPath: path).lastPathComponent)"
            }
            return "Editing..."
        case "Write":
            if let path = input["file_path"] {
                return "Write: \(URL(fileURLWithPath: path).lastPathComponent)"
            }
            return "Writing..."
        case "WebFetch":
            if let url = input["url"] {
                return "Fetching: \(url.prefix(30))..."
            }
            return "Fetching..."
        case "WebSearch":
            if let query = input["query"] {
                return "Search: \(query.prefix(30))"
            }
            return "Searching web..."
        default:
            return name
        }
    }
}

/// Info about a subagent tool (simpler version for events)
public struct SubagentToolInfo: Sendable, Codable {
    public let id: String
    public let name: String
    public let input: [String: String]
    public let isCompleted: Bool
    public let timestamp: String?

    public init(id: String, name: String, input: [String: String], isCompleted: Bool, timestamp: String?) {
        self.id = id
        self.name = name
        self.input = input
        self.isCompleted = isCompleted
        self.timestamp = timestamp
    }
}
