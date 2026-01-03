//
//  ChatHistoryManager.swift
//  ClaudeNook
//

import ClaudeNookShared
import Combine
import Foundation

@MainActor
class ChatHistoryManager: ObservableObject {
    static let shared = ChatHistoryManager()

    @Published private(set) var histories: [String: [ChatHistoryItem]] = [:]
    @Published private(set) var agentDescriptions: [String: [String: String]] = [:]

    private var loadedSessions: Set<String> = []
    private var cancellables = Set<AnyCancellable>()

    private init() {
        SessionStore.shared.sessionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.updateFromSessions(sessions)
            }
            .store(in: &cancellables)
    }

    // MARK: - Public API

    func history(for sessionId: String) -> [ChatHistoryItem] {
        histories[sessionId] ?? []
    }

    func isLoaded(sessionId: String) -> Bool {
        loadedSessions.contains(sessionId)
    }

    func loadFromFile(sessionId: String, cwd: String) async {
        guard !loadedSessions.contains(sessionId) else { return }
        loadedSessions.insert(sessionId)
        await SessionStore.shared.process(.loadHistory(sessionId: sessionId, cwd: cwd))
    }

    func syncFromFile(sessionId: String, cwd: String) async {
        let messages = await ConversationParser.shared.parseFullConversation(
            sessionId: sessionId,
            cwd: cwd
        )
        let completedTools = await ConversationParser.shared.completedToolIds(for: sessionId)
        let toolResults = await ConversationParser.shared.toolResults(for: sessionId)
        let structuredResults = await ConversationParser.shared.structuredResults(for: sessionId)

        let payload = FileUpdatePayload(
            sessionId: sessionId,
            cwd: cwd,
            messages: messages,
            isIncremental: false,  // Full sync
            completedToolIds: completedTools,
            toolResults: toolResults,
            structuredResults: structuredResults
        )

        await SessionStore.shared.process(.fileUpdated(payload))
    }

    func clearHistory(for sessionId: String) {
        loadedSessions.remove(sessionId)
        histories.removeValue(forKey: sessionId)
        Task {
            await SessionStore.shared.process(.sessionEnded(sessionId: sessionId))
        }
    }

    // MARK: - State Updates

    private func updateFromSessions(_ sessions: [SessionState]) {
        var newHistories: [String: [ChatHistoryItem]] = [:]
        var newAgentDescriptions: [String: [String: String]] = [:]
        for session in sessions {
            let filteredItems = filterOutSubagentTools(session.chatItems)
            newHistories[session.sessionId] = filteredItems
            newAgentDescriptions[session.sessionId] = session.subagentState.agentDescriptions
            loadedSessions.insert(session.sessionId)
        }
        histories = newHistories
        agentDescriptions = newAgentDescriptions
    }

    private func filterOutSubagentTools(_ items: [ChatHistoryItem]) -> [ChatHistoryItem] {
        var subagentToolIds = Set<String>()
        for item in items {
            if case .toolCall(let tool) = item.type, tool.name == "Task" {
                for subagentTool in tool.subagentTools {
                    subagentToolIds.insert(subagentTool.id)
                }
            }
        }

        return items.filter { !subagentToolIds.contains($0.id) }
    }
}
