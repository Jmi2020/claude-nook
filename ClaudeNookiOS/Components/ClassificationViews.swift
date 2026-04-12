//
//  ClassificationViews.swift
//  ClaudeNookiOS
//
//  UI components for displaying AI session classification.
//

import ClaudeNookShared
import SwiftUI

// MARK: - Category Chip

struct CategoryChip: View {
    let category: SessionCategory

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: category.icon)
                .font(.system(size: 9))
            Text(category.shortLabel)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(category.color.opacity(0.9))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(category.color.opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - Progress Badge

struct ProgressBadge: View {
    let progress: SessionProgress

    var body: some View {
        Text(progress.displayLabel)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(progress.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(progress.color.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: - Category Extensions

extension SessionCategory {
    var icon: String {
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

    var shortLabel: String {
        switch self {
        case .coding: return "Coding"
        case .debugging: return "Debug"
        case .research: return "Research"
        case .refactoring: return "Refactor"
        case .testing: return "Testing"
        case .deploying: return "Deploy"
        case .configuring: return "Config"
        case .reviewing: return "Review"
        case .planning: return "Plan"
        case .other: return "Other"
        }
    }

    var color: Color {
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

// MARK: - Progress Extensions

extension SessionProgress {
    var displayLabel: String {
        switch self {
        case .starting: return "Starting"
        case .inProgress: return "In Progress"
        case .wrappingUp: return "Wrapping Up"
        case .blocked: return "Blocked"
        case .waiting: return "Waiting"
        }
    }

    var color: Color {
        switch self {
        case .starting: return .white.opacity(0.5)
        case .inProgress: return TerminalColors.prompt
        case .wrappingUp: return TerminalColors.green
        case .blocked: return TerminalColors.amber
        case .waiting: return .white.opacity(0.5)
        }
    }
}
