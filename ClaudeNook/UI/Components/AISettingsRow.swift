//
//  AISettingsRow.swift
//  ClaudeNook
//
//  Settings UI for AI session classification (Ollama / LM Studio)
//

import SwiftUI

struct AISettingsRow: View {
    @State private var isExpanded = false
    @State private var isHovered = false
    @State private var isEnabled = AppSettings.aiClassificationEnabled
    @State private var backendType = AIBackendType(rawValue: AppSettings.aiBackendType) ?? .ollama
    @State private var modelName = AppSettings.aiModelName
    @State private var interval = ClassificationInterval(rawValue: AppSettings.aiClassificationInterval) ?? .thirtySeconds
    @State private var backendAvailable: Bool? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Main row - toggle + expand
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "brain")
                        .font(.system(size: 12))
                        .foregroundColor(textColor)
                        .frame(width: 16)

                    Text("AI Classification")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(textColor)

                    Spacer()

                    // Status indicator
                    if isEnabled {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 6, height: 6)
                            Text(statusText)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    } else {
                        Text("Off")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                    }

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

            // Expanded settings
            if isExpanded {
                VStack(spacing: 8) {
                    // Enable toggle
                    SettingToggle(label: "Enable", isOn: $isEnabled) {
                        AppSettings.aiClassificationEnabled = isEnabled
                    }

                    if isEnabled {
                        // Backend picker
                        SettingPicker(
                            label: "Backend",
                            options: AIBackendType.allCases.map { ($0.rawValue, $0.displayName) },
                            selected: backendType.rawValue
                        ) { value in
                            if let type = AIBackendType(rawValue: value) {
                                backendType = type
                                AppSettings.aiBackendType = value
                                checkBackendAvailability()
                            }
                        }

                        // Model name
                        SettingTextField(label: "Model", text: $modelName) {
                            AppSettings.aiModelName = modelName
                        }

                        // Interval picker
                        SettingPicker(
                            label: "Interval",
                            options: ClassificationInterval.allCases.map { (String($0.rawValue), $0.displayName) },
                            selected: String(interval.rawValue)
                        ) { value in
                            if let intVal = Int(value), let newInterval = ClassificationInterval(rawValue: intVal) {
                                interval = newInterval
                                AppSettings.aiClassificationInterval = intVal
                            }
                        }
                    }
                }
                .padding(.leading, 28)
                .padding(.trailing, 12)
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
        }
        .onAppear {
            isEnabled = AppSettings.aiClassificationEnabled
            backendType = AIBackendType(rawValue: AppSettings.aiBackendType) ?? .ollama
            modelName = AppSettings.aiModelName
            interval = ClassificationInterval(rawValue: AppSettings.aiClassificationInterval) ?? .thirtySeconds
            if isEnabled {
                checkBackendAvailability()
            }
        }
    }

    private var textColor: Color {
        .white.opacity(isHovered ? 1.0 : 0.7)
    }

    private var statusColor: Color {
        switch backendAvailable {
        case .some(true): return TerminalColors.green
        case .some(false): return TerminalColors.red
        case .none: return .white.opacity(0.3)
        }
    }

    private var statusText: String {
        switch backendAvailable {
        case .some(true): return backendType.displayName
        case .some(false): return "Not Found"
        case .none: return "Checking..."
        }
    }

    private func checkBackendAvailability() {
        backendAvailable = nil
        Task {
            let backend: any LLMBackend = backendType == .ollama
                ? OllamaBackend(model: modelName)
                : LMStudioBackend(model: modelName)
            let available = await backend.isAvailable()
            await MainActor.run {
                backendAvailable = available
            }
        }
    }
}

// MARK: - Reusable Setting Controls

private struct SettingToggle: View {
    let label: String
    @Binding var isOn: Bool
    let onChange: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .scaleEffect(0.7)
                .onChange(of: isOn) { _ in onChange() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }
}

private struct SettingPicker: View {
    let label: String
    let options: [(value: String, display: String)]
    let selected: String
    let onChange: (String) -> Void

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
            Spacer()
            HStack(spacing: 2) {
                ForEach(options, id: \.value) { option in
                    Button {
                        onChange(option.value)
                    } label: {
                        Text(option.display)
                            .font(.system(size: 11, weight: selected == option.value ? .medium : .regular))
                            .foregroundColor(selected == option.value ? .white : .white.opacity(0.4))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(selected == option.value ? Color.white.opacity(0.12) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }
}

private struct SettingTextField: View {
    let label: String
    @Binding var text: String
    let onCommit: () -> Void

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
            Spacer()
            TextField("", text: $text, onCommit: onCommit)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .textFieldStyle(.plain)
                .frame(maxWidth: 120)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.06))
                )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }
}
