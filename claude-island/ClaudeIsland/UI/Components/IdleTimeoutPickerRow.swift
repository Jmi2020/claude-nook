//
//  IdleTimeoutPickerRow.swift
//  ClaudeIsland
//
//  Idle timeout selection picker for settings menu
//

import Combine
import SwiftUI

// MARK: - IdleTimeoutSelector

class IdleTimeoutSelector: ObservableObject {
    static let shared = IdleTimeoutSelector()

    @Published var isPickerExpanded: Bool = false

    private init() {}
}

// MARK: - IdleTimeoutPickerRow

struct IdleTimeoutPickerRow: View {
    @ObservedObject var selector: IdleTimeoutSelector
    @State private var isHovered = false
    @State private var selectedTimeout: IdleTimeout = AppSettings.idleTimeout

    private var isExpanded: Bool {
        selector.isPickerExpanded
    }

    private func setExpanded(_ value: Bool) {
        selector.isPickerExpanded = value
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main row - shows current selection
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    setExpanded(!isExpanded)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "clock")
                        .font(.system(size: 12))
                        .foregroundColor(textColor)
                        .frame(width: 16)

                    Text("Idle Cleanup")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(textColor)

                    Spacer()

                    Text(selectedTimeout.displayName)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }

            // Expanded timeout list
            if isExpanded {
                VStack(spacing: 2) {
                    ForEach(IdleTimeout.allCases, id: \.self) { timeout in
                        IdleTimeoutOptionRow(
                            timeout: timeout,
                            isSelected: selectedTimeout == timeout
                        ) {
                            selectedTimeout = timeout
                            AppSettings.idleTimeout = timeout
                        }
                    }
                }
                .padding(.leading, 28)
                .padding(.top, 4)
            }
        }
        .onAppear {
            selectedTimeout = AppSettings.idleTimeout
        }
    }

    private var textColor: Color {
        .white.opacity(isHovered ? 1.0 : 0.7)
    }
}

// MARK: - IdleTimeoutOptionRow

private struct IdleTimeoutOptionRow: View {
    let timeout: IdleTimeout
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isSelected ? TerminalColors.green : Color.white.opacity(0.2))
                    .frame(width: 6, height: 6)

                Text(timeout.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(isHovered ? 1.0 : 0.7))

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(TerminalColors.green)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
