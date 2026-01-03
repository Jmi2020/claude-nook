//
//  SessionState.swift
//  ClaudeNookShared
//
//  Unified state model for a Claude session.
//  Consolidates all state that was previously spread across multiple components.
//

import Foundation

/// Complete state for a single Claude session
/// This is the single source of truth - all state reads and writes go through SessionStore
public struct SessionState: Equatable, Identifiable, Sendable, Codable {
    // MARK: - Identity

    public let sessionId: String
    public let cwd: String
    public let projectName: String

    // MARK: - Instance Metadata

    public var pid: Int?
    public var tty: String?
    public var isInTmux: Bool

    // MARK: - State Machine

    /// Current phase in the session lifecycle
    public var phase: SessionPhase

    // MARK: - Chat History

    /// All chat items for this session (replaces ChatHistoryManager.histories)
    public var chatItems: [ChatHistoryItem]

    // MARK: - Tool Tracking

    /// Unified tool tracker (replaces 6+ dictionaries in ChatHistoryManager)
    public var toolTracker: ToolTracker

    // MARK: - Subagent State

    /// State for Task tools and their nested subagent tools
    public var subagentState: SubagentState

    // MARK: - Conversation Info (from JSONL parsing)

    public var conversationInfo: ConversationInfo

    // MARK: - Clear Reconciliation

    /// When true, the next file update should reconcile chatItems with parser state
    /// This removes pre-/clear items that no longer exist in the JSONL
    public var needsClearReconciliation: Bool

    // MARK: - Timestamps

    public var lastActivity: Date
    public var createdAt: Date

    // MARK: - Identifiable

    public var id: String { sessionId }

    // MARK: - Initialization

    public nonisolated init(
        sessionId: String,
        cwd: String,
        projectName: String? = nil,
        pid: Int? = nil,
        tty: String? = nil,
        isInTmux: Bool = false,
        phase: SessionPhase = .idle,
        chatItems: [ChatHistoryItem] = [],
        toolTracker: ToolTracker = ToolTracker(),
        subagentState: SubagentState = SubagentState(),
        conversationInfo: ConversationInfo = ConversationInfo(
            summary: nil, lastMessage: nil, lastMessageRole: nil,
            lastToolName: nil, firstUserMessage: nil, lastUserMessageDate: nil
        ),
        needsClearReconciliation: Bool = false,
        lastActivity: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.projectName = projectName ?? URL(fileURLWithPath: cwd).lastPathComponent
        self.pid = pid
        self.tty = tty
        self.isInTmux = isInTmux
        self.phase = phase
        self.chatItems = chatItems
        self.toolTracker = toolTracker
        self.subagentState = subagentState
        self.conversationInfo = conversationInfo
        self.needsClearReconciliation = needsClearReconciliation
        self.lastActivity = lastActivity
        self.createdAt = createdAt
    }

    // MARK: - Derived Properties

    /// Whether this session needs user attention
    public var needsAttention: Bool {
        phase.needsAttention
    }

    /// The active permission context, if any
    public var activePermission: PermissionContext? {
        if case .waitingForApproval(let ctx) = phase {
            return ctx
        }
        return nil
    }

    // MARK: - UI Convenience Properties

    /// Stable identity for SwiftUI (combines PID and sessionId for animation stability)
    public var stableId: String {
        if let pid = pid {
            return "\(pid)-\(sessionId)"
        }
        return sessionId
    }

    /// Display title: summary > first user message > project name
    public var displayTitle: String {
        conversationInfo.summary ?? conversationInfo.firstUserMessage ?? projectName
    }

    /// Best hint for matching window title
    public var windowHint: String {
        conversationInfo.summary ?? projectName
    }

    /// Pending tool name if waiting for approval
    public var pendingToolName: String? {
        activePermission?.toolName
    }

    /// Pending tool use ID
    public var pendingToolId: String? {
        activePermission?.toolUseId
    }

    /// Formatted pending tool input for display
    public var pendingToolInput: String? {
        activePermission?.formattedInput
    }

    /// Last message content
    public var lastMessage: String? {
        conversationInfo.lastMessage
    }

    /// Last message role
    public var lastMessageRole: String? {
        conversationInfo.lastMessageRole
    }

    /// Last tool name
    public var lastToolName: String? {
        conversationInfo.lastToolName
    }

    /// Summary
    public var summary: String? {
        conversationInfo.summary
    }

    /// First user message
    public var firstUserMessage: String? {
        conversationInfo.firstUserMessage
    }

    /// Last user message date
    public var lastUserMessageDate: Date? {
        conversationInfo.lastUserMessageDate
    }

    /// Whether the session can be interacted with
    public var canInteract: Bool {
        phase.needsAttention
    }
}

// MARK: - Tool Tracker

/// Unified tool tracking - replaces multiple dictionaries in ChatHistoryManager
public struct ToolTracker: Equatable, Sendable, Codable {
    /// Tools currently in progress, keyed by tool_use_id
    public var inProgress: [String: ToolInProgress]

    /// All tool IDs we've seen (for deduplication)
    public var seenIds: Set<String>

    /// Last JSONL file offset for incremental parsing
    public var lastSyncOffset: UInt64

    /// Last sync timestamp
    public var lastSyncTime: Date?

    public nonisolated init(
        inProgress: [String: ToolInProgress] = [:],
        seenIds: Set<String> = [],
        lastSyncOffset: UInt64 = 0,
        lastSyncTime: Date? = nil
    ) {
        self.inProgress = inProgress
        self.seenIds = seenIds
        self.lastSyncOffset = lastSyncOffset
        self.lastSyncTime = lastSyncTime
    }

    /// Mark a tool ID as seen, returns true if it was new
    public nonisolated mutating func markSeen(_ id: String) -> Bool {
        seenIds.insert(id).inserted
    }

    /// Check if a tool ID has been seen
    public nonisolated func hasSeen(_ id: String) -> Bool {
        seenIds.contains(id)
    }

    /// Start tracking a tool
    public nonisolated mutating func startTool(id: String, name: String) {
        guard markSeen(id) else { return }
        inProgress[id] = ToolInProgress(
            id: id,
            name: name,
            startTime: Date(),
            phase: .running
        )
    }

    /// Complete a tool
    public nonisolated mutating func completeTool(id: String, success: Bool) {
        inProgress.removeValue(forKey: id)
    }
}

/// A tool currently in progress
public struct ToolInProgress: Equatable, Sendable, Codable {
    public let id: String
    public let name: String
    public let startTime: Date
    public var phase: ToolInProgressPhase

    public init(id: String, name: String, startTime: Date, phase: ToolInProgressPhase) {
        self.id = id
        self.name = name
        self.startTime = startTime
        self.phase = phase
    }
}

/// Phase of a tool in progress
public enum ToolInProgressPhase: String, Equatable, Sendable, Codable {
    case starting
    case running
    case pendingApproval
}

// MARK: - Subagent State

/// State for Task (subagent) tools
public struct SubagentState: Equatable, Sendable, Codable {
    /// Active Task tools, keyed by task tool_use_id
    public var activeTasks: [String: TaskContext]

    /// Ordered stack of active task IDs (most recent last) - used for proper tool assignment
    /// When multiple Tasks run in parallel, we use insertion order rather than timestamps
    public var taskStack: [String]

    /// Mapping of agentId to Task description (for AgentOutputTool display)
    public var agentDescriptions: [String: String]

    public nonisolated init(activeTasks: [String: TaskContext] = [:], taskStack: [String] = [], agentDescriptions: [String: String] = [:]) {
        self.activeTasks = activeTasks
        self.taskStack = taskStack
        self.agentDescriptions = agentDescriptions
    }

    /// Whether there's an active subagent
    public nonisolated var hasActiveSubagent: Bool {
        !activeTasks.isEmpty
    }

    /// Start tracking a Task tool
    public nonisolated mutating func startTask(taskToolId: String, description: String? = nil) {
        activeTasks[taskToolId] = TaskContext(
            taskToolId: taskToolId,
            startTime: Date(),
            agentId: nil,
            description: description,
            subagentTools: []
        )
    }

    /// Stop tracking a Task tool
    public nonisolated mutating func stopTask(taskToolId: String) {
        activeTasks.removeValue(forKey: taskToolId)
    }

    /// Set the agentId for a Task (called when agent file is discovered)
    public nonisolated mutating func setAgentId(_ agentId: String, for taskToolId: String) {
        activeTasks[taskToolId]?.agentId = agentId
        if let description = activeTasks[taskToolId]?.description {
            agentDescriptions[agentId] = description
        }
    }

    /// Add a subagent tool to a specific Task by ID
    public nonisolated mutating func addSubagentToolToTask(_ tool: SubagentToolCall, taskId: String) {
        activeTasks[taskId]?.subagentTools.append(tool)
    }

    /// Set all subagent tools for a specific Task (used when updating from agent file)
    public nonisolated mutating func setSubagentTools(_ tools: [SubagentToolCall], for taskId: String) {
        activeTasks[taskId]?.subagentTools = tools
    }

    /// Add a subagent tool to the most recent active Task
    public nonisolated mutating func addSubagentTool(_ tool: SubagentToolCall) {
        // Find most recent active task (for parallel Task support)
        guard let mostRecentTaskId = activeTasks.keys.max(by: {
            (activeTasks[$0]?.startTime ?? .distantPast) < (activeTasks[$1]?.startTime ?? .distantPast)
        }) else { return }

        activeTasks[mostRecentTaskId]?.subagentTools.append(tool)
    }

    /// Update the status of a subagent tool across all active Tasks
    public nonisolated mutating func updateSubagentToolStatus(toolId: String, status: ToolStatus) {
        for taskId in activeTasks.keys {
            if let index = activeTasks[taskId]?.subagentTools.firstIndex(where: { $0.id == toolId }) {
                activeTasks[taskId]?.subagentTools[index].status = status
                return
            }
        }
    }
}

/// Context for an active Task tool
public struct TaskContext: Equatable, Sendable, Codable {
    public let taskToolId: String
    public let startTime: Date
    public var agentId: String?
    public var description: String?
    public var subagentTools: [SubagentToolCall]

    public init(taskToolId: String, startTime: Date, agentId: String?, description: String?, subagentTools: [SubagentToolCall]) {
        self.taskToolId = taskToolId
        self.startTime = startTime
        self.agentId = agentId
        self.description = description
        self.subagentTools = subagentTools
    }
}
