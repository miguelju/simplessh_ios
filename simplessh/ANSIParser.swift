//
//  ANSIParser.swift
//  simplessh
//
//  Created by Miguel Jackson on 3/21/26.
//

import SwiftUI

/// Parses ANSI escape codes into styled AttributedString for terminal rendering.
/// Supports SGR (colors, bold, italic, underline, dim, reverse), 256-color,
/// true color (24-bit), and strips non-visual sequences (cursor, OSC, etc.).
struct ANSIParser {

    // MARK: - Standard ANSI Colors

    /// Standard 4-bit ANSI colors (normal intensity)
    private static let standardColors: [Color] = [
        Color(red: 0, green: 0, blue: 0),         // 0: Black
        Color(red: 0.8, green: 0, blue: 0),        // 1: Red
        Color(red: 0, green: 0.8, blue: 0),        // 2: Green
        Color(red: 0.8, green: 0.8, blue: 0),      // 3: Yellow
        Color(red: 0.3, green: 0.3, blue: 1.0),    // 4: Blue
        Color(red: 0.8, green: 0, blue: 0.8),      // 5: Magenta
        Color(red: 0, green: 0.8, blue: 0.8),      // 6: Cyan
        Color(red: 0.75, green: 0.75, blue: 0.75), // 7: White (light gray)
    ]

    /// Bright ANSI colors
    private static let brightColors: [Color] = [
        Color(red: 0.5, green: 0.5, blue: 0.5),    // 0: Bright Black (dark gray)
        Color(red: 1.0, green: 0.3, blue: 0.3),    // 1: Bright Red
        Color(red: 0.3, green: 1.0, blue: 0.3),    // 2: Bright Green
        Color(red: 1.0, green: 1.0, blue: 0.3),    // 3: Bright Yellow
        Color(red: 0.5, green: 0.5, blue: 1.0),    // 4: Bright Blue
        Color(red: 1.0, green: 0.3, blue: 1.0),    // 5: Bright Magenta
        Color(red: 0.3, green: 1.0, blue: 1.0),    // 6: Bright Cyan
        Color(red: 1.0, green: 1.0, blue: 1.0),    // 7: Bright White
    ]

    // MARK: - Text State

    /// Current text rendering state tracked while parsing
    private struct TextState {
        var foreground: Color
        var background: Color? = nil
        var bold: Bool = false
        var dim: Bool = false
        var italic: Bool = false
        var underline: Bool = false
        var strikethrough: Bool = false
        var reverse: Bool = false

        /// The default terminal foreground color (configurable)
        let defaultForeground: Color
        let defaultFont: Font
        let boldFont: Font

        init(defaultForeground: Color = .green,
             defaultFont: Font = .system(.body, design: .monospaced),
             boldFont: Font = .system(.body, design: .monospaced).bold()) {
            self.defaultForeground = defaultForeground
            self.defaultFont = defaultFont
            self.boldFont = boldFont
            self.foreground = defaultForeground
        }

        mutating func reset() {
            foreground = defaultForeground
            background = nil
            bold = false
            dim = false
            italic = false
            underline = false
            strikethrough = false
            reverse = false
        }
    }

    // MARK: - Public API

    /// Parses a raw terminal output string with ANSI codes into a styled AttributedString.
    /// - Parameters:
    ///   - input: Raw terminal output containing ANSI escape codes
    ///   - defaultForeground: Default text color (used for reset and unstyled text)
    ///   - defaultFont: Default font for regular text
    ///   - boldFont: Font used for bold text
    static func parse(_ input: String,
                      defaultForeground: Color = .green,
                      defaultFont: Font = .system(.body, design: .monospaced),
                      boldFont: Font = .system(.body, design: .monospaced).bold()) -> AttributedString {
        var result = AttributedString()
        var state = TextState(defaultForeground: defaultForeground, defaultFont: defaultFont, boldFont: boldFont)
        var index = input.startIndex
        var textBuffer = ""

        while index < input.endIndex {
            let char = input[index]

            // ESC character (0x1B)
            if char == "\u{1B}" {
                // Flush any buffered text
                if !textBuffer.isEmpty {
                    result += styledString(textBuffer, state: state)
                    textBuffer = ""
                }

                let next = input.index(after: index)
                guard next < input.endIndex else {
                    index = next
                    break
                }

                switch input[next] {
                case "[":
                    // CSI sequence: ESC [ ... final_byte
                    index = input.index(after: next)
                    index = parseCSI(input, from: index, state: &state)
                case "]":
                    // OSC sequence: ESC ] ... (BEL or ST) — strip it
                    index = input.index(after: next)
                    index = skipOSC(input, from: index)
                case "(", ")":
                    // Character set designation — skip 1 more byte
                    index = input.index(after: next)
                    if index < input.endIndex {
                        index = input.index(after: index)
                    }
                default:
                    // Unknown ESC sequence — skip ESC and next char
                    index = input.index(after: next)
                }
            }
            // Strip carriage return (handle \r\n as just \n)
            else if char == "\r" {
                index = input.index(after: index)
            }
            else {
                textBuffer.append(char)
                index = input.index(after: index)
            }
        }

        // Flush remaining text
        if !textBuffer.isEmpty {
            result += styledString(textBuffer, state: state)
        }

        return result
    }

    // MARK: - CSI Parsing

    /// Parses a CSI (Control Sequence Introducer) sequence starting after "ESC [".
    /// Returns the index after the final byte of the sequence.
    private static func parseCSI(_ input: String, from start: String.Index, state: inout TextState) -> String.Index {
        var index = start
        var paramString = ""

        // Collect parameter bytes (0x30-0x3F) and intermediate bytes (0x20-0x2F)
        while index < input.endIndex {
            let c = input[index]
            let scalar = c.asciiValue ?? 0

            // Final byte (0x40-0x7E) terminates the sequence
            if scalar >= 0x40 && scalar <= 0x7E {
                let finalByte = c
                index = input.index(after: index)

                if finalByte == "m" {
                    // SGR — Select Graphic Rendition
                    applySGR(paramString, state: &state)
                }
                // All other CSI sequences (cursor movement, clearing, etc.) are stripped
                return index
            }

            paramString.append(c)
            index = input.index(after: index)
        }

        return index
    }

    // MARK: - SGR (Select Graphic Rendition)

    /// Applies SGR parameters to the text state.
    private static func applySGR(_ paramString: String, state: inout TextState) {
        // Empty or "0" means reset
        if paramString.isEmpty {
            state.reset()
            return
        }

        let params = paramString.split(separator: ";", omittingEmptySubsequences: false)
            .map { Int($0) ?? 0 }
        var i = 0

        while i < params.count {
            let code = params[i]

            switch code {
            case 0:
                state.reset()

            // Styles
            case 1: state.bold = true
            case 2: state.dim = true
            case 3: state.italic = true
            case 4: state.underline = true
            case 7: state.reverse = true
            case 9: state.strikethrough = true

            // Reset styles
            case 21, 22:
                state.bold = false
                state.dim = false
            case 23: state.italic = false
            case 24: state.underline = false
            case 27: state.reverse = false
            case 29: state.strikethrough = false

            // Standard foreground colors (30-37)
            case 30...37:
                state.foreground = standardColors[code - 30]

            // Default foreground
            case 39:
                state.foreground = state.defaultForeground

            // Standard background colors (40-47)
            case 40...47:
                state.background = standardColors[code - 40]

            // Default background
            case 49:
                state.background = nil

            // Bright foreground colors (90-97)
            case 90...97:
                state.foreground = brightColors[code - 90]

            // Bright background colors (100-107)
            case 100...107:
                state.background = brightColors[code - 100]

            // Extended foreground color
            case 38:
                if i + 1 < params.count {
                    if params[i + 1] == 5, i + 2 < params.count {
                        // 256-color: ESC[38;5;Nm
                        state.foreground = color256(params[i + 2])
                        i += 2
                    } else if params[i + 1] == 2, i + 4 < params.count {
                        // True color: ESC[38;2;R;G;Bm
                        state.foreground = Color(
                            red: Double(params[i + 2]) / 255.0,
                            green: Double(params[i + 3]) / 255.0,
                            blue: Double(params[i + 4]) / 255.0
                        )
                        i += 4
                    }
                }

            // Extended background color
            case 48:
                if i + 1 < params.count {
                    if params[i + 1] == 5, i + 2 < params.count {
                        // 256-color: ESC[48;5;Nm
                        state.background = color256(params[i + 2])
                        i += 2
                    } else if params[i + 1] == 2, i + 4 < params.count {
                        // True color: ESC[48;2;R;G;Bm
                        state.background = Color(
                            red: Double(params[i + 2]) / 255.0,
                            green: Double(params[i + 3]) / 255.0,
                            blue: Double(params[i + 4]) / 255.0
                        )
                        i += 4
                    }
                }

            default:
                break
            }

            i += 1
        }
    }

    // MARK: - 256-Color Lookup

    /// Converts a 256-color index to a SwiftUI Color.
    private static func color256(_ index: Int) -> Color {
        switch index {
        case 0...7:
            return standardColors[index]
        case 8...15:
            return brightColors[index - 8]
        case 16...231:
            // 6x6x6 color cube
            let adjusted = index - 16
            let r = adjusted / 36
            let g = (adjusted % 36) / 6
            let b = adjusted % 6
            return Color(
                red: r == 0 ? 0 : (Double(r) * 40.0 + 55.0) / 255.0,
                green: g == 0 ? 0 : (Double(g) * 40.0 + 55.0) / 255.0,
                blue: b == 0 ? 0 : (Double(b) * 40.0 + 55.0) / 255.0
            )
        case 232...255:
            // Grayscale ramp
            let gray = Double(index - 232) * 10.0 + 8.0
            return Color(red: gray / 255.0, green: gray / 255.0, blue: gray / 255.0)
        default:
            return .green
        }
    }

    // MARK: - OSC Stripping

    /// Skips an OSC (Operating System Command) sequence (ESC ] ... BEL/ST).
    /// Used for terminal title, hyperlinks, etc.
    private static func skipOSC(_ input: String, from start: String.Index) -> String.Index {
        var index = start
        while index < input.endIndex {
            let c = input[index]
            // BEL (0x07) terminates OSC
            if c == "\u{07}" {
                return input.index(after: index)
            }
            // ST (ESC \) terminates OSC
            if c == "\u{1B}" {
                let next = input.index(after: index)
                if next < input.endIndex && input[next] == "\\" {
                    return input.index(after: next)
                }
            }
            index = input.index(after: index)
        }
        return index
    }

    // MARK: - Styled String Construction

    /// Creates an AttributedString with the given text and current rendering state.
    private static func styledString(_ text: String, state: TextState) -> AttributedString {
        var attrs = AttributeContainer()

        // Foreground / background (handle reverse)
        let fg = state.reverse ? (state.background ?? .black) : state.foreground
        let bg = state.reverse ? state.foreground : state.background

        attrs.foregroundColor = state.dim ? fg.opacity(0.6) : fg
        if let bg {
            attrs.backgroundColor = bg
        }

        // Font
        attrs.font = state.bold ? state.boldFont : state.defaultFont

        // Underline
        if state.underline {
            attrs.underlineStyle = .single
        }

        // Strikethrough
        if state.strikethrough {
            attrs.strikethroughStyle = .single
        }

        var result = AttributedString(text)
        result.mergeAttributes(attrs)
        return result
    }
}
