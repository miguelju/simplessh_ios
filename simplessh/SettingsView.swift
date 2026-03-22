//
//  SettingsView.swift
//  simplessh
//
//  Created by Miguel Jackson on 3/21/26.
//

import SwiftUI

/// Settings view for customizing terminal appearance
struct SettingsView: View {
    @ObservedObject private var settings = TerminalSettingsStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // Live preview
                Section {
                    terminalPreview
                }

                // Unified theme picker
                Section("Theme") {
                    Picker("Theme", selection: $settings.themeName) {
                        ForEach(TerminalTheme.allCases) { theme in
                            HStack(spacing: 10) {
                                // Color swatch using theme's font
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(themeBackground(theme))
                                    .overlay(
                                        Text("A")
                                            .font(theme.terminalFont.font(size: 13).bold())
                                            .foregroundStyle(themeForeground(theme))
                                    )
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                    )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(theme.rawValue)
                                    if theme != .custom {
                                        Text("\(theme.terminalFont.rawValue) \(Int(theme.fontSize))pt")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .tag(theme.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                // Custom font settings (only when Custom theme is selected)
                if settings.theme == .custom {
                    Section("Custom Font") {
                        Picker("Font Family", selection: $settings.customFontName) {
                            ForEach(TerminalFont.allCases) { font in
                                Text(font.rawValue)
                                    .font(font.font(size: 16))
                                    .tag(font.rawValue)
                            }
                        }

                        HStack {
                            Text("Size")
                            Spacer()
                            Text("\(Int(settings.customFontSize)) pt")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $settings.customFontSize, in: 8...28, step: 1) {
                            Text("Font Size")
                        }
                    }

                    Section("Custom Colors") {
                        ColorPicker("Text Color", selection: customForegroundBinding)
                        ColorPicker("Background Color", selection: customBackgroundBinding)
                    }
                }

                // Reset
                Section {
                    Button("Reset to Defaults") {
                        resetToDefaults()
                    }
                    .foregroundStyle(.red)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Theme Swatch Helpers

    private func themeForeground(_ theme: TerminalTheme) -> Color {
        if theme == .custom {
            return settings.foregroundColor
        }
        return theme.foreground
    }

    private func themeBackground(_ theme: TerminalTheme) -> Color {
        if theme == .custom {
            return settings.backgroundColor
        }
        return theme.background
    }

    // MARK: - Terminal Preview

    private var terminalPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("user@server:~$ ls -la")
                .font(settings.font)
                .foregroundStyle(settings.foregroundColor)
            Text("total 42")
                .font(settings.font)
                .foregroundStyle(settings.foregroundColor.opacity(0.8))
            Text("drwxr-xr-x  5 user staff  160 Mar 21 16:00 .")
                .font(settings.font)
                .foregroundStyle(settings.foregroundColor.opacity(0.8))
            HStack(spacing: 0) {
                Text("user@server:~$ ")
                    .font(settings.font)
                    .foregroundStyle(settings.foregroundColor)
                RoundedRectangle(cornerRadius: 1)
                    .fill(settings.foregroundColor)
                    .frame(width: CGFloat(settings.fontSize) * 0.6, height: CGFloat(settings.fontSize))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(settings.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    // MARK: - Custom Color Bindings

    private var customForegroundBinding: Binding<Color> {
        Binding(
            get: { Color(red: settings.customFgR, green: settings.customFgG, blue: settings.customFgB) },
            set: { newColor in
                if let components = newColor.cgColor?.components, components.count >= 3 {
                    settings.customFgR = Double(components[0])
                    settings.customFgG = Double(components[1])
                    settings.customFgB = Double(components[2])
                }
            }
        )
    }

    private var customBackgroundBinding: Binding<Color> {
        Binding(
            get: { Color(red: settings.customBgR, green: settings.customBgG, blue: settings.customBgB) },
            set: { newColor in
                if let components = newColor.cgColor?.components, components.count >= 3 {
                    settings.customBgR = Double(components[0])
                    settings.customBgG = Double(components[1])
                    settings.customBgB = Double(components[2])
                }
            }
        )
    }

    // MARK: - Actions

    private func resetToDefaults() {
        settings.themeName = TerminalTheme.classicGreen.rawValue
        settings.customFontName = TerminalFont.system.rawValue
        settings.customFontSize = 14
        settings.customFgR = 0.2
        settings.customFgG = 1.0
        settings.customFgB = 0.2
        settings.customBgR = 0.0
        settings.customBgG = 0.0
        settings.customBgB = 0.0
    }
}

#Preview {
    SettingsView()
}
