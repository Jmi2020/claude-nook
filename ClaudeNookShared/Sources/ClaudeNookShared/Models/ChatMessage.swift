//
//  ChatMessage.swift
//  ClaudeNookShared
//
//  Models for conversation messages parsed from JSONL.
//

import Foundation

public struct ChatMessage: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let role: ChatRole
    public let timestamp: Date
    public let content: [MessageBlock]

    public init(id: String, role: ChatRole, timestamp: Date, content: [MessageBlock]) {
        self.id = id
        self.role = role
        self.timestamp = timestamp
        self.content = content
    }

    public static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }

    /// Plain text content combined
    public var textContent: String {
        content.compactMap { block in
            if case .text(let text) = block {
                return text
            }
            return nil
        }.joined(separator: "\n")
    }
}

public enum ChatRole: String, Equatable, Sendable, Codable {
    case user
    case assistant
    case system
}

public enum MessageBlock: Equatable, Identifiable, Sendable, Codable {
    case text(String)
    case toolUse(ToolUseBlock)
    case thinking(String)
    case interrupted

    public var id: String {
        switch self {
        case .text(let text):
            return "text-\(text.prefix(20).hashValue)"
        case .toolUse(let block):
            return "tool-\(block.id)"
        case .thinking(let text):
            return "thinking-\(text.prefix(20).hashValue)"
        case .interrupted:
            return "interrupted"
        }
    }

    /// Type prefix for generating stable IDs
    public nonisolated var typePrefix: String {
        switch self {
        case .text: return "text"
        case .toolUse: return "tool"
        case .thinking: return "thinking"
        case .interrupted: return "interrupted"
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case toolUse
    }

    private enum BlockType: String, Codable {
        case text
        case toolUse
        case thinking
        case interrupted
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(BlockType.self, forKey: .type)

        switch type {
        case .text:
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        case .toolUse:
            let block = try container.decode(ToolUseBlock.self, forKey: .toolUse)
            self = .toolUse(block)
        case .thinking:
            let text = try container.decode(String.self, forKey: .text)
            self = .thinking(text)
        case .interrupted:
            self = .interrupted
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .text(let text):
            try container.encode(BlockType.text, forKey: .type)
            try container.encode(text, forKey: .text)
        case .toolUse(let block):
            try container.encode(BlockType.toolUse, forKey: .type)
            try container.encode(block, forKey: .toolUse)
        case .thinking(let text):
            try container.encode(BlockType.thinking, forKey: .type)
            try container.encode(text, forKey: .text)
        case .interrupted:
            try container.encode(BlockType.interrupted, forKey: .type)
        }
    }
}

public struct ToolUseBlock: Equatable, Sendable, Codable {
    public let id: String
    public let name: String
    public let input: [String: String]

    public init(id: String, name: String, input: [String: String]) {
        self.id = id
        self.name = name
        self.input = input
    }

    /// Short preview of the tool input
    public var preview: String {
        if let filePath = input["file_path"] ?? input["path"] {
            return filePath
        }
        if let command = input["command"] {
            let firstLine = command.components(separatedBy: "\n").first ?? command
            return String(firstLine.prefix(50))
        }
        if let pattern = input["pattern"] {
            return pattern
        }
        return input.values.first.map { String($0.prefix(50)) } ?? ""
    }
}
