//
//  MacCategoryChip.swift
//  ClaudeNook
//
//  Compact category indicator for the macOS notch UI.
//

import ClaudeNookShared
import SwiftUI

struct MacCategoryChip: View {
    let category: SessionCategory

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: category.macIcon)
                .font(.system(size: 8))
            Text(category.macLabel)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(category.macColor.opacity(0.85))
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(category.macColor.opacity(0.1))
        .clipShape(Capsule())
    }
}

extension SessionCategory {
    var macIcon: String {
        switch self {
        case .coding: return "chevron.left.forwardslash.chevron.right"
        case .debugging: return "ant.fill"
        case .research: return "magnifyingglass"
        case .refactoring: return "arrow.triangle.2.circlepath"
        case .testing: return "checkmark.diamond"
        case .deploying: return "icloud.and.arrow.up"
        case .configuring: return "gearshape"
        case .reviewing: return "eye"
        case .planning: return "list.bullet.clipboard"
        case .other: return "ellipsis.circle"
        }
    }

    var macLabel: String {
        switch self {
        case .coding: return "Code"
        case .debugging: return "Debug"
        case .research: return "Research"
        case .refactoring: return "Refactor"
        case .testing: return "Test"
        case .deploying: return "Deploy"
        case .configuring: return "Config"
        case .reviewing: return "Review"
        case .planning: return "Plan"
        case .other: return "Other"
        }
    }

    var macColor: Color {
        switch self {
        case .coding: return TerminalColors.blue
        case .debugging: return TerminalColors.red
        case .research: return TerminalColors.cyan
        case .refactoring: return TerminalColors.magenta
        case .testing: return TerminalColors.green
        case .deploying: return TerminalColors.amber
        case .configuring: return TerminalColors.amber
        case .reviewing: return TerminalColors.cyan
        case .planning: return TerminalColors.blue
        case .other: return .white.opacity(0.5)
        }
    }
}
