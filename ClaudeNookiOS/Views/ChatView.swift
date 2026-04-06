//
//  ChatView.swift
//  ClaudeNookiOS
//
//  Chat history view for a Claude Code session.
//  Shows user messages, assistant responses, and tool calls.
//

import ClaudeNookShared
import SwiftUI

struct ChatView: View {
    let session: SessionStateLight
    @EnvironmentObject var sessionStore: iOSSessionStore

    private var chatItems: [ChatHistoryItem] {
        // Get live items from session store (updated via SUBSCRIBE)
        if let liveSession = sessionStore.sessions.first(where: { $0.sessionId == session.sessionId }) {
            return liveSession.chatItems
        }
        return session.chatItems
    }

    var body: some View {
        Group {
            if chatItems.isEmpty {
                emptyState
            } else {
                messageList
            }
        }
        .navigationTitle(session.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.nookBackground)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.3))
            Text("No messages yet")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.4))
            Text("Messages will appear as the session progresses")
                .font(.caption)
                .foregroundColor(.white.opacity(0.25))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(chatItems) { item in
                        ChatItemView(item: item)
                            .id(item.id)
                    }
                }
                .padding()
            }
            .onAppear {
                // Scroll to bottom
                if let lastId = chatItems.last?.id {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            }
            .onChange(of: chatItems.count) { _ in
                if let lastId = chatItems.last?.id {
                    withAnimation {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }
}

// MARK: - Chat Item View

struct ChatItemView: View {
    let item: ChatHistoryItem

    var body: some View {
        switch item.type {
        case .user(let text):
            UserMessageView(text: text)
        case .assistant(let text):
            AssistantMessageView(text: text)
        case .toolCall(let tool):
            ToolCallView(tool: tool)
        case .thinking(let text):
            ThinkingView(text: text)
        case .interrupted:
            InterruptedView()
        }
    }
}

// MARK: - User Message

struct UserMessageView: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("You")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(TerminalColors.blue)
                .frame(width: 40, alignment: .leading)

            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .textSelection(.enabled)
        }
        .padding(12)
        .background(Color.nookSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Assistant Message

struct AssistantMessageView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundColor(.white.opacity(0.9))
            .textSelection(.enabled)
            .padding(12)
    }
}

// MARK: - Tool Call

struct ToolCallView: View {
    let tool: ToolCallItem
    @State private var isExpanded = false

    private var statusColor: Color {
        switch tool.status {
        case .running:
            return TerminalColors.amber
        case .success:
            return TerminalColors.green
        case .error:
            return TerminalColors.red
        case .waitingForApproval:
            return TerminalColors.amber
        case .interrupted:
            return TerminalColors.red
        }
    }

    private var statusIcon: String {
        switch tool.status {
        case .running:
            return "arrow.triangle.2.circlepath"
        case .success:
            return "checkmark.circle"
        case .error:
            return "xmark.circle"
        case .waitingForApproval:
            return "exclamationmark.triangle"
        case .interrupted:
            return "stop.circle"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Tool header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 11))
                        .foregroundColor(statusColor)

                    Text(tool.name)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(TerminalColors.prompt)

                    if !tool.input.isEmpty {
                        Text(tool.inputPreview)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    // Input
                    if !tool.input.isEmpty {
                        ForEach(Array(tool.input.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                            HStack(alignment: .top, spacing: 4) {
                                Text("\(key):")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.5))
                                Text(value)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.7))
                                    .textSelection(.enabled)
                            }
                        }
                    }

                    // Result
                    if let result = tool.result, !result.isEmpty {
                        Divider()
                            .background(Color.white.opacity(0.1))
                        Text(String(result.prefix(500)))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                            .textSelection(.enabled)
                    }
                }
                .padding(.leading, 20)
            }
        }
        .padding(10)
        .background(TerminalColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Thinking View

struct ThinkingView: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "brain")
                .font(.system(size: 10))
                .foregroundColor(TerminalColors.magenta.opacity(0.6))
            Text(String(text.prefix(200)))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
                .lineLimit(3)
        }
        .padding(8)
    }
}

// MARK: - Interrupted View

struct InterruptedView: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "stop.circle")
                .font(.system(size: 11))
                .foregroundColor(TerminalColors.red.opacity(0.7))
            Text("Interrupted")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(TerminalColors.red.opacity(0.7))
        }
        .padding(8)
    }
}
