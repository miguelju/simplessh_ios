//
//  TerminalSettings.swift
//  simplessh
//
//  Created by Miguel Jackson on 3/21/26.
//

import SwiftUI
import Combine
import UIKit

/// App-wide appearance mode (light, dark, or follow system)
enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    /// Converts to an optional ColorScheme for `.preferredColorScheme()`
    /// Returns nil for system (follows device setting)
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

/// Available monospaced fonts for the terminal
enum TerminalFont: String, CaseIterable, Identifiable {
    case meslo = "MesloLGS NF"
    case system = "System Mono"
    case menlo = "Menlo"
    case courier = "Courier"
    case courierNew = "Courier New"
    case sfMono = "SF Mono"
    case monaco = "Monaco"

    var id: String { rawValue }

    /// The family name used to resolve the bundled Nerd Font (see FontRegistrar).
    static let mesloFamilyName = "MesloLGS NF"

    /// The SwiftUI Font for a given size
    func font(size: CGFloat) -> Font {
        switch self {
        case .meslo:
            return Self.mesloFont(size: size, bold: false)
        case .system:
            return .system(size: size, design: .monospaced)
        case .menlo:
            return .custom("Menlo", size: size)
        case .courier:
            return .custom("Courier", size: size)
        case .courierNew:
            return .custom("Courier New", size: size)
        case .sfMono:
            return .custom("SFMono-Regular", size: size)
        case .monaco:
            return .custom("Monaco", size: size)
        }
    }

    /// Bold variant
    func boldFont(size: CGFloat) -> Font {
        switch self {
        case .meslo:
            return Self.mesloFont(size: size, bold: true)
        case .system:
            return .system(size: size, design: .monospaced).bold()
        case .menlo:
            return .custom("Menlo-Bold", size: size)
        case .courier:
            return .custom("Courier-Bold", size: size)
        case .courierNew:
            return .custom("CourierNewPS-BoldMT", size: size)
        case .sfMono:
            return .custom("SFMono-Bold", size: size)
        case .monaco:
            return .custom("Monaco", size: size).bold()
        }
    }

    /// Resolves the bundled MesloLGS NF face by family name + bold trait. Using
    /// the family name (rather than a hard-coded PostScript name) reliably picks
    /// the registered regular/bold faces; falls back to the system monospaced
    /// font if the bundled font failed to register.
    private static func mesloFont(size: CGFloat, bold: Bool) -> Font {
        var descriptor = UIFontDescriptor(fontAttributes: [.family: mesloFamilyName])
        if bold, let boldDescriptor = descriptor.withSymbolicTraits(.traitBold) {
            descriptor = boldDescriptor
        }
        let uiFont = UIFont(descriptor: descriptor, size: size)
        // If the family isn't available, UIKit returns a system fallback whose
        // familyName won't match — use the design-monospaced system font instead.
        if uiFont.familyName != mesloFamilyName {
            return .system(size: size, design: .monospaced)
        }
        return Font(uiFont)
    }
}

/// Unified terminal theme bundling font, size, and colors
enum TerminalTheme: String, CaseIterable, Identifiable {
    case classicGreen = "Classic Green"
    case amber = "Amber"
    case cyan = "Cyan"
    case white = "White"
    case solarized = "Solarized"
    case dracula = "Dracula"
    case ohMyZsh = "Oh My Zsh"
    case custom = "Custom"

    var id: String { rawValue }

    /// The font family for this theme. All presets use the bundled MesloLGS NF
    /// so Powerline / Nerd Font prompt icons render (it's a clean monospaced
    /// font for ordinary text too). The Custom theme respects the user's pick.
    var terminalFont: TerminalFont {
        switch self {
        case .custom: return .system
        default:      return .meslo
        }
    }

    /// The font size for this theme
    var fontSize: CGFloat {
        switch self {
        case .classicGreen: return 14
        case .amber:        return 14
        case .cyan:         return 14
        case .white:        return 14
        case .solarized:    return 14
        case .dracula:      return 14
        case .ohMyZsh:      return 13
        case .custom:       return 14
        }
    }

    var foreground: Color {
        switch self {
        case .classicGreen: return Color(red: 0.2, green: 1.0, blue: 0.2)
        case .amber:        return Color(red: 1.0, green: 0.75, blue: 0.0)
        case .cyan:         return Color(red: 0.0, green: 0.9, blue: 0.9)
        case .white:        return Color(red: 0.9, green: 0.9, blue: 0.9)
        case .solarized:    return Color(red: 0.51, green: 0.58, blue: 0.59)
        case .dracula:      return Color(red: 0.97, green: 0.97, blue: 0.95)
        case .ohMyZsh:      return Color(red: 0.83, green: 0.83, blue: 0.83)
        case .custom:       return .green
        }
    }

    var background: Color {
        switch self {
        case .classicGreen: return .black
        case .amber:        return Color(red: 0.05, green: 0.05, blue: 0.05)
        case .cyan:         return Color(red: 0.0, green: 0.05, blue: 0.1)
        case .white:        return Color(red: 0.1, green: 0.1, blue: 0.1)
        case .solarized:    return Color(red: 0.0, green: 0.17, blue: 0.21)
        case .dracula:      return Color(red: 0.16, green: 0.16, blue: 0.21)
        case .ohMyZsh:      return Color(red: 0.12, green: 0.12, blue: 0.12)
        case .custom:       return .black
        }
    }
}

/// Observable terminal settings persisted via @AppStorage
@MainActor
class TerminalSettingsStore: ObservableObject {
    static let shared = TerminalSettingsStore()

    /// App appearance mode (system, light, or dark)
    @AppStorage("app_appearance") var appearanceName: String = AppAppearance.system.rawValue

    /// The currently selected appearance mode
    var appearance: AppAppearance {
        get { AppAppearance(rawValue: appearanceName) ?? .system }
        set { appearanceName = newValue.rawValue }
    }

    /// Selected theme (reuses same @AppStorage key for backward compatibility)
    @AppStorage("terminal_colorPreset") var themeName: String = TerminalTheme.classicGreen.rawValue

    /// Custom-mode overrides (only active when theme == .custom)
    @AppStorage("terminal_font") var customFontName: String = TerminalFont.system.rawValue
    @AppStorage("terminal_fontSize") var customFontSize: Double = 14
    @AppStorage("terminal_customFgR") var customFgR: Double = 0.2
    @AppStorage("terminal_customFgG") var customFgG: Double = 1.0
    @AppStorage("terminal_customFgB") var customFgB: Double = 0.2
    @AppStorage("terminal_customBgR") var customBgR: Double = 0.0
    @AppStorage("terminal_customBgG") var customBgG: Double = 0.0
    @AppStorage("terminal_customBgB") var customBgB: Double = 0.0

    /// The currently selected theme
    var theme: TerminalTheme {
        get { TerminalTheme(rawValue: themeName) ?? .classicGreen }
        set { themeName = newValue.rawValue }
    }

    /// The active font (from theme or custom override)
    var terminalFont: TerminalFont {
        if theme == .custom {
            return TerminalFont(rawValue: customFontName) ?? .system
        }
        return theme.terminalFont
    }

    /// The active font size (from theme or custom override)
    var fontSize: Double {
        if theme == .custom {
            return customFontSize
        }
        return Double(theme.fontSize)
    }

    var foregroundColor: Color {
        if theme == .custom {
            return Color(red: customFgR, green: customFgG, blue: customFgB)
        }
        return theme.foreground
    }

    var backgroundColor: Color {
        if theme == .custom {
            return Color(red: customBgR, green: customBgG, blue: customBgB)
        }
        return theme.background
    }

    var font: Font {
        terminalFont.font(size: CGFloat(fontSize))
    }

    var boldFont: Font {
        terminalFont.boldFont(size: CGFloat(fontSize))
    }
}
