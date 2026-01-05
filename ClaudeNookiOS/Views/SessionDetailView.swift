//
//  SessionDetailView.swift
//  ClaudeNookiOS
//
//  Detail view for a single Claude session.
//

import ClaudeNookShared
import SwiftUI

struct SessionDetailView: View {
    let session: SessionStateLight

    @EnvironmentObject var sessionStore: iOSSessionStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.nookBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Session Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            StatusIndicator(phase: session.phase)

                            Text(session.phase.displayName)
                                .font(.headline)
                                .foregroundStyle(.white)
                        }

                        Text(session.projectName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.nookSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Display Title
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Summary")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(session.displayTitle)
                            .font(.body)
                            .foregroundStyle(.white)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.nookSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Pending Tool (if any)
                    if let toolName = session.pendingToolName {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Pending Approval")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack {
                                Image(systemName: toolIcon(for: toolName))
                                    .foregroundStyle(.orange)

                                Text(toolName)
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            }

                            if let toolInput = session.pendingToolInput {
                                Text(toolInput)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(5)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.nookSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.orange, lineWidth: 2)
                        )
                    }

                    // Session Info
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Session Info")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        LabeledContent("Session ID") {
                            Text(session.sessionId.prefix(8) + "...")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }

                        LabeledContent("Created") {
                            Text(session.createdAt, style: .relative)
                                .foregroundStyle(.secondary)
                        }

                        LabeledContent("Last Activity") {
                            Text(session.lastActivity, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.nookSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }
        }
        .navigationTitle(session.projectName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.nookBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.6))
                        .font(.title2)
                }
            }
        }
    }

    private func toolIcon(for tool: String) -> String {
        switch tool.lowercased() {
        case "bash": return "terminal"
        case "read": return "doc.text"
        case "write": return "pencil"
        case "edit": return "pencil.line"
        case "glob": return "folder.badge.gearshape"
        case "grep": return "magnifyingglass"
        case "task": return "person.2"
        case "webfetch": return "globe"
        case "websearch": return "magnifyingglass.circle"
        default: return "wrench"
        }
    }
}

#Preview {
    NavigationStack {
        SessionDetailView(session: SessionStateLight(
            sessionId: "test-123",
            projectName: "my-project",
            phase: .processing,
            lastActivity: Date(),
            createdAt: Date().addingTimeInterval(-3600),
            displayTitle: "Help me implement a new feature for the app",
            pendingToolName: nil,
            pendingToolInput: nil
        ))
    }
    .environmentObject(iOSSessionStore())
    .preferredColorScheme(.dark)
}
