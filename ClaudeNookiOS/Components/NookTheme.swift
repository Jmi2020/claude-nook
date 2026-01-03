//
//  NookTheme.swift
//  ClaudeNookiOS
//
//  Dark theme colors and styles for the iOS app.
//  Matches the macOS Nook aesthetic.
//

import SwiftUI

// MARK: - Nook Color Theme

extension Color {
    /// Dark background color matching macOS app
    static let nookBackground = Color(red: 0.08, green: 0.08, blue: 0.10)

    /// Surface color for cards and inputs
    static let nookSurface = Color(red: 0.14, green: 0.14, blue: 0.16)

    /// Accent color (Claude blue)
    static let nookAccent = Color(red: 0.45, green: 0.55, blue: 0.95)

    /// Secondary surface
    static let nookSurfaceSecondary = Color(red: 0.18, green: 0.18, blue: 0.20)
}

// MARK: - Terminal Colors (matching macOS)

struct TerminalColors {
    static let green = Color(red: 0.4, green: 0.75, blue: 0.45)
    static let amber = Color(red: 1.0, green: 0.7, blue: 0.0)
    static let red = Color(red: 1.0, green: 0.3, blue: 0.3)
    static let cyan = Color(red: 0.0, green: 0.8, blue: 0.8)
    static let blue = Color(red: 0.4, green: 0.6, blue: 1.0)
    static let magenta = Color(red: 0.8, green: 0.4, blue: 0.8)
    static let dim = Color.white.opacity(0.4)
    static let dimmer = Color.white.opacity(0.2)
    static let prompt = Color(red: 0.85, green: 0.47, blue: 0.34) // Claude orange #d97857
    static let background = Color.white.opacity(0.05)
    static let backgroundHover = Color.white.opacity(0.1)
}

// MARK: - ShapeStyle Extension

extension ShapeStyle where Self == Color {
    /// Nook accent color for use in foregroundStyle
    static var nookAccent: Color { .nookAccent }

    /// Nook background color
    static var nookBackground: Color { .nookBackground }

    /// Nook surface color
    static var nookSurface: Color { .nookSurface }
}

// MARK: - Nook Button Style

struct NookButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(isPrimary ? .white : .nookAccent)
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .background(isPrimary ? Color.nookAccent : Color.nookSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

// MARK: - Nook TextField Style

struct NookTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(Color.nookSurface)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Approval Button Style

struct NookApprovalButtonStyle: ButtonStyle {
    let isApprove: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .background(isApprove ? Color.green : Color.red.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}
