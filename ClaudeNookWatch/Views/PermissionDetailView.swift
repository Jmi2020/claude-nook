//
//  PermissionDetailView.swift
//  ClaudeNookWatch
//
//  Full-screen permission approval with tool details.
//

import ClaudeNookShared
import SwiftUI

struct PermissionDetailView: View {
    let request: PermissionRequest
    @EnvironmentObject var sessionStore: WatchSessionStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Tool name
                Text(request.toolName)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(WatchColors.amber)

                Text(request.projectName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Tool input preview
                if let input = request.toolInput, !input.isEmpty {
                    Text(String(input.prefix(100)))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.nookSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                // Approve / Deny buttons
                HStack(spacing: 12) {
                    Button {
                        Task {
                            await sessionStore.deny(request: request)
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WatchColors.red)

                    Button {
                        Task {
                            await sessionStore.approve(request: request)
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.title3)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WatchColors.green)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Approval")
    }
}
