//
//  ChatHistoryItem.swift
//  ClaudeNookShared
//
//  Models for chat history display.
//

import Foundation

public struct ChatHistoryItem: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let type: ChatHistoryItemType
    public let timestamp: Date

    public init(id: String, type: ChatHistoryItemType, timestamp: Date) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
    }

    public static func == (lhs: ChatHistoryItem, rhs: ChatHistoryItem) -> Bool {
        lhs.id == rhs.id && lhs.type == rhs.type
    }
}

public enum ChatHistoryItemType: Equatable, Sendable, Codable {
    case user(String)
    case assistant(String)
    case toolCall(ToolCallItem)
    case thinking(String)
    case interrupted

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type
        case content
        case toolCall
    }

    private enum ItemType: String, Codable {
        case user
        case assistant
        case toolCall
        case thinking
        case interrupted
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ItemType.self, forKey: .type)

        switch type {
        case .user:
            let content = try container.decode(String.self, forKey: .content)
            self = .user(content)
        case .assistant:
            let content = try container.decode(String.self, forKey: .content)
            self = .assistant(content)
        case .toolCall:
            let item = try container.decode(ToolCallItem.self, forKey: .toolCall)
            self = .toolCall(item)
        case .thinking:
            let content = try container.decode(String.self, forKey: .content)
            self = .thinking(content)
        case .interrupted:
            self = .interrupted
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .user(let content):
            try container.encode(ItemType.user, forKey: .type)
            try container.encode(content, forKey: .content)
        case .assistant(let content):
            try container.encode(ItemType.assistant, forKey: .type)
            try container.encode(content, forKey: .content)
        case .toolCall(let item):
            try container.encode(ItemType.toolCall, forKey: .type)
            try container.encode(item, forKey: .toolCall)
        case .thinking(let content):
            try container.encode(ItemType.thinking, forKey: .type)
            try container.encode(content, forKey: .content)
        case .interrupted:
            try container.encode(ItemType.interrupted, forKey: .type)
        }
    }
}

public struct ToolCallItem: Equatable, Sendable, Codable {
    public let name: String
    public let input: [String: String]
    public var status: ToolStatus
    public var result: String?
    public var structuredResult: ToolResultData?

    /// For Task tools: nested subagent tool calls
    public var subagentTools: [SubagentToolCall]

    public init(name: String, input: [String: String], status: ToolStatus, result: String? = nil, structuredResult: ToolResultData? = nil, subagentTools: [SubagentToolCall] = []) {
        self.name = name
        self.input = input
        self.status = status
        self.result = result
        self.structuredResult = structuredResult
        self.subagentTools = subagentTools
    }

    /// Preview text for the tool (input-based)
    public var inputPreview: String {
        if let filePath = input["file_path"] ?? input["path"] {
            return URL(fileURLWithPath: filePath).lastPathComponent
        }
        if let command = input["command"] {
            let firstLine = command.components(separatedBy: "\n").first ?? command
            return String(firstLine.prefix(60))
        }
        if let pattern = input["pattern"] {
            return pattern
        }
        if let query = input["query"] {
            return query
        }
        if let url = input["url"] {
            return url
        }
        if let agentId = input["agentId"] {
            let blocking = input["block"] == "true"
            return blocking ? "Waiting..." : "Checking \(agentId.prefix(8))..."
        }
        return input.values.first.map { String($0.prefix(60)) } ?? ""
    }

    /// Status display text for the tool
    public var statusDisplay: ToolStatusDisplay {
        if status == .running {
            return ToolStatusDisplay.running(for: name, input: input)
        }
        if status == .waitingForApproval {
            return ToolStatusDisplay(text: "Waiting for approval...", isRunning: true)
        }
        if status == .interrupted {
            return ToolStatusDisplay(text: "Interrupted", isRunning: false)
        }
        return ToolStatusDisplay.completed(for: name, result: structuredResult)
    }

    // Custom Equatable implementation to handle structuredResult
    public static func == (lhs: ToolCallItem, rhs: ToolCallItem) -> Bool {
        lhs.name == rhs.name &&
        lhs.input == rhs.input &&
        lhs.status == rhs.status &&
        lhs.result == rhs.result &&
        lhs.structuredResult == rhs.structuredResult &&
        lhs.subagentTools == rhs.subagentTools
    }

    // MARK: - Codable (custom because ToolResultData needs special handling)

    private enum CodingKeys: String, CodingKey {
        case name, input, status, result, subagentTools
        // Note: structuredResult is not serialized over the wire for iOS
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        input = try container.decode([String: String].self, forKey: .input)
        status = try container.decode(ToolStatus.self, forKey: .status)
        result = try container.decodeIfPresent(String.self, forKey: .result)
        subagentTools = try container.decodeIfPresent([SubagentToolCall].self, forKey: .subagentTools) ?? []
        structuredResult = nil // Not serialized
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(input, forKey: .input)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(result, forKey: .result)
        try container.encode(subagentTools, forKey: .subagentTools)
        // structuredResult not serialized
    }
}

/// Info about a conversation (parsed from JSONL)
public struct ConversationInfo: Equatable, Sendable, Codable {
    public let summary: String?
    public let lastMessage: String?
    public let lastMessageRole: String?  // "user", "assistant", or "tool"
    public let lastToolName: String?  // Tool name if lastMessageRole is "tool"
    public let firstUserMessage: String?  // Fallback title when no summary
    public let lastUserMessageDate: Date?  // Timestamp of last user message (for stable sorting)

    public init(summary: String?, lastMessage: String?, lastMessageRole: String?, lastToolName: String?, firstUserMessage: String?, lastUserMessageDate: Date?) {
        self.summary = summary
        self.lastMessage = lastMessage
        self.lastMessageRole = lastMessageRole
        self.lastToolName = lastToolName
        self.firstUserMessage = firstUserMessage
        self.lastUserMessageDate = lastUserMessageDate
    }
}
