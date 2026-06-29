//
//  TerminalEmulator.swift
//  simplessh
//
//  A stateful, incremental VT100/xterm-style terminal emulator.
//
//  Unlike a one-shot string parser, this keeps a live screen grid, cursor,
//  scroll region, SGR state, bounded scrollback, and an alternate-screen
//  buffer — fed bytes as they arrive over the PTY. That makes full-screen TUI
//  apps (vim, htop, less, `clear`) render correctly and restores the shell
//  scrollback when they exit. The parser is a persistent state machine, so
//  escape sequences split across network reads are handled naturally.
//

import SwiftUI

final class TerminalEmulator {

    // MARK: - Cell & Style

    /// Visual attributes of a cell. `fg`/`bg` are nil when the terminal default
    /// should be used; `reverse` is resolved against the defaults at render time.
    struct Style: Equatable {
        var fg: Color? = nil
        var bg: Color? = nil
        var bold = false
        var dim = false
        var italic = false
        var underline = false
        var strikethrough = false
        var reverse = false
    }

    struct Cell: Equatable {
        var ch: Character = " "
        var style = Style()
    }

    // MARK: - Geometry

    let cols: Int
    let rows: Int

    // MARK: - Buffers

    /// The active screen (main or alternate), `rows` lines of `cols` cells.
    private var screen: [[Cell]]
    /// Main screen saved while the alternate screen is active.
    private var savedScreen: [[Cell]]?
    /// Lines that have scrolled off the top of the main screen.
    private var scrollback: [[Cell]] = []
    private var usingAlt = false
    private let maxScrollback = 2000

    // MARK: - Cursor & State

    private var row = 0
    private var col = 0
    private var savedRow = 0
    private var savedCol = 0
    private var savedStyle = Style()
    /// Deferred end-of-line wrap (DEC autowrap): set after writing the last
    /// column; the next printable char wraps first.
    private var wrapNext = false

    /// Scroll region (inclusive, 0-based).
    private var top = 0
    private var bottom = 0

    private var cur = Style()
    private var autowrap = true

    // MARK: - Parser state machine

    private enum ParseState { case ground, esc, csi, osc, charset }
    private var pstate: ParseState = .ground
    private var csiBuffer = ""
    private var oscBuffer = ""
    private var oscPrevWasEsc = false

    /// Bytes the terminal needs to send *back* to the host in response to query
    /// sequences (DSR/DA). The owner drains this after `feed(_:)` and writes it
    /// to the PTY. Answering these is what lets prompts that probe the terminal
    /// (Powerlevel10k / instant prompt, gitstatus) draw immediately instead of
    /// waiting for the first keystroke.
    private var pendingReply = ""

    /// Returns and clears any queued host-bound reply (see `pendingReply`).
    func drainReply() -> String? {
        guard !pendingReply.isEmpty else { return nil }
        let reply = pendingReply
        pendingReply = ""
        return reply
    }

    // MARK: - Init

    init(cols: Int = 80, rows: Int = 24) {
        self.cols = max(1, cols)
        self.rows = max(1, rows)
        self.screen = TerminalEmulator.makeBlankScreen(rows: self.rows, cols: self.cols)
        self.bottom = self.rows - 1
    }

    /// Resets the emulator to a clean state (used at the start of a session).
    func reset() {
        screen = TerminalEmulator.makeBlankScreen(rows: rows, cols: cols)
        savedScreen = nil
        scrollback.removeAll(keepingCapacity: true)
        usingAlt = false
        row = 0; col = 0
        savedRow = 0; savedCol = 0; savedStyle = Style()
        wrapNext = false
        top = 0; bottom = rows - 1
        cur = Style()
        autowrap = true
        pstate = .ground
        csiBuffer = ""
        oscPrevWasEsc = false
    }

    private static func makeBlankScreen(rows: Int, cols: Int) -> [[Cell]] {
        Array(repeating: Array(repeating: Cell(), count: cols), count: rows)
    }

    private func blankCell() -> Cell {
        // Erased cells take the current background (so apps that set a bg then
        // clear get the expected fill), but no other attributes.
        Cell(ch: " ", style: Style(bg: cur.bg))
    }

    private func blankLine() -> [Cell] {
        Array(repeating: blankCell(), count: cols)
    }

    // MARK: - Feed (incremental parse)

    func feed(_ text: String) {
        // Iterate by Unicode scalar, NOT Character: Swift treats "\r\n" as a
        // single Character (grapheme cluster), which would bypass the \r and \n
        // control handling entirely and concatenate every line. Scalars keep
        // CR and LF separate.
        for scalar in text.unicodeScalars {
            let ch = Character(scalar)
            switch pstate {
            case .ground:  ground(ch)
            case .esc:     escape(ch)
            case .csi:     csi(ch)
            case .osc:     osc(ch)
            case .charset: pstate = .ground  // consume one designator byte
            }
        }
    }

    private func ground(_ ch: Character) {
        switch ch {
        case "\u{1B}": pstate = .esc
        case "\r": col = 0; wrapNext = false
        case "\n", "\u{0B}", "\u{0C}": lineFeed()   // LF, VT, FF
        case "\u{08}": backspace()
        case "\t": tab()
        case "\u{07}": break                         // BEL
        default:
            if let a = ch.asciiValue, a < 0x20 { break } // other C0 controls
            putChar(sanitizedGlyph(ch))
        }
    }

    private func escape(_ ch: Character) {
        switch ch {
        case "[": csiBuffer = ""; pstate = .csi
        case "]": oscBuffer = ""; oscPrevWasEsc = false; pstate = .osc
        case "(", ")", "*", "+": pstate = .charset
        case "7": savedRow = row; savedCol = col; savedStyle = cur; pstate = .ground   // DECSC
        case "8": row = savedRow; col = savedCol; cur = savedStyle; clampCursor(); pstate = .ground // DECRC
        case "M": reverseIndex(); pstate = .ground                                     // RI
        case "D": lineFeed(); pstate = .ground                                         // IND
        case "E": col = 0; lineFeed(); pstate = .ground                                // NEL
        case "c": reset(); pstate = .ground                                            // RIS
        default: pstate = .ground                                                      // =, >, etc.
        }
    }

    private func csi(_ ch: Character) {
        let scalar = ch.asciiValue ?? 0
        if scalar >= 0x40 && scalar <= 0x7E {
            dispatchCSI(final: ch)
            pstate = .ground
        } else {
            csiBuffer.append(ch)
        }
    }

    private func osc(_ ch: Character) {
        // OSC terminated by BEL or ST (ESC \). We capture the body so we can
        // answer color queries (OSC 10/11/12 with "?"), which some prompts
        // (e.g. Powerlevel10k) probe at startup before drawing.
        if ch == "\u{07}" { finishOSC(); return }
        if oscPrevWasEsc {
            finishOSC()  // ST: ESC \ — the preceding ESC was the terminator start
            return
        }
        if ch == "\u{1B}" { oscPrevWasEsc = true; return }
        oscBuffer.append(ch)
    }

    private func finishOSC() {
        defer { pstate = .ground; oscPrevWasEsc = false; oscBuffer = "" }
        debugLogQuery("OSC", oscBuffer)
        // Color queries: "10;?" (foreground), "11;?" (background), "12;?" (cursor).
        // Reply with a plausible value so capability detection completes. The app
        // uses dark terminals, so report a dark background / light foreground.
        let parts = oscBuffer.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, parts[1] == "?" else { return }
        let color: String
        switch parts[0] {
        case "10", "12": color = "rgb:ffff/ffff/ffff" // foreground / cursor: white
        case "11":       color = "rgb:0000/0000/0000" // background: black
        default: return
        }
        pendingReply += "\u{1B}]\(parts[0]);\(color)\u{07}"
    }

    // MARK: - Character output

    private func putChar(_ ch: Character) {
        if wrapNext {
            col = 0
            lineFeed()
            wrapNext = false
        }
        if col >= cols {
            if autowrap { col = 0; lineFeed() } else { col = cols - 1 }
        }
        screen[row][col] = Cell(ch: ch, style: cur)
        if col == cols - 1 {
            wrapNext = autowrap
        } else {
            col += 1
        }
    }

    private func backspace() {
        wrapNext = false
        if col > 0 { col -= 1 }
    }

    private func tab() {
        wrapNext = false
        let next = ((col / 8) + 1) * 8
        col = min(next, cols - 1)
    }

    private func lineFeed() {
        wrapNext = false
        if row == bottom {
            scrollUp()
        } else if row < rows - 1 {
            row += 1
        }
    }

    private func reverseIndex() {
        wrapNext = false
        if row == top {
            scrollDown()
        } else if row > 0 {
            row -= 1
        }
    }

    private func scrollUp() {
        let removed = screen[top]
        if top == 0 && !usingAlt {
            scrollback.append(removed)
            if scrollback.count > maxScrollback {
                scrollback.removeFirst(scrollback.count - maxScrollback)
            }
        }
        screen.remove(at: top)
        screen.insert(blankLine(), at: bottom)
    }

    private func scrollDown() {
        screen.insert(blankLine(), at: top)
        screen.remove(at: bottom + 1)
    }

    // MARK: - CSI dispatch

    private func dispatchCSI(final: Character) {
        let isPrivate = csiBuffer.hasPrefix("?")
        let body = isPrivate ? String(csiBuffer.dropFirst()) : csiBuffer
        let params = body.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        func p(_ i: Int, _ def: Int) -> Int {
            guard i < params.count else { return def }
            return params[i] == 0 && def != 0 && body.isEmpty ? def : params[i]
        }
        func arg(_ i: Int, _ def: Int) -> Int {
            guard i < params.count, params[i] != 0 else { return def }
            return params[i]
        }

        if isPrivate {
            switch final {
            case "h": setPrivateMode(params, enabled: true)
            case "l": setPrivateMode(params, enabled: false)
            case "n" where arg(0, 0) == 6:
                // DECXCPR — extended cursor position report
                pendingReply += "\u{1B}[?\(row + 1);\(col + 1)R"
            default: break
            }
            return
        }

        switch final {
        case "A": row = max(top, row - arg(0, 1)); wrapNext = false
        case "B": row = min(bottom, row + arg(0, 1)); wrapNext = false
        case "C": col = min(cols - 1, col + arg(0, 1)); wrapNext = false
        case "D": col = max(0, col - arg(0, 1)); wrapNext = false
        case "E": col = 0; row = min(bottom, row + arg(0, 1)); wrapNext = false
        case "F": col = 0; row = max(top, row - arg(0, 1)); wrapNext = false
        case "G", "`": col = clampCol(arg(0, 1) - 1); wrapNext = false
        case "d": row = clampRow(arg(0, 1) - 1); wrapNext = false
        case "H", "f":
            row = clampRow(arg(0, 1) - 1)
            col = clampCol(arg(1, 1) - 1)
            wrapNext = false
        case "J": eraseInDisplay(arg(0, 0))
        case "K": eraseInLine(arg(0, 0))
        case "L": insertLines(arg(0, 1))
        case "M": deleteLines(arg(0, 1))
        case "P": deleteChars(arg(0, 1))
        case "X": eraseChars(arg(0, 1))
        case "@": insertBlanks(arg(0, 1))
        case "m": applySGR(params)
        case "r":
            let t = clampRow(arg(0, 1) - 1)
            let b = clampRow(arg(1, rows) - 1)
            if t < b { top = t; bottom = b; row = top; col = 0 }
        case "s": savedRow = row; savedCol = col; savedStyle = cur
        case "u": row = savedRow; col = savedCol; cur = savedStyle; clampCursor()
        case "n": // DSR — Device Status Report
            debugLogQuery("DSR", csiBuffer)
            switch arg(0, 0) {
            case 5: pendingReply += "\u{1B}[0n"                               // terminal OK
            case 6: pendingReply += "\u{1B}[\(row + 1);\(col + 1)R"          // cursor position
            default: break
            }
        case "c": // DA — Device Attributes
            debugLogQuery("DA", csiBuffer)
            if csiBuffer.hasPrefix(">") {
                pendingReply += "\u{1B}[>0;10;0c"   // secondary DA (xterm-like)
            } else {
                pendingReply += "\u{1B}[?1;2c"      // primary DA: VT100 with Advanced Video
            }
        case "t": // XTWINOPS — window/text-area size reports
            switch arg(0, 0) {
            case 18: pendingReply += "\u{1B}[8;\(rows);\(cols)t"            // text area, chars
            case 14: pendingReply += "\u{1B}[4;\(rows * 16);\(cols * 8)t"   // text area, pixels (approx)
            case 16: pendingReply += "\u{1B}[6;16;8t"                       // cell size, pixels (approx)
            default: break
            }
        case "q" where csiBuffer.hasPrefix(">"): // XTVERSION request (CSI > q)
            debugLogQuery("XTVERSION", csiBuffer)
            pendingReply += "\u{1B}P>|simplessh(1.0)\u{1B}\\"   // DCS > | name ST
        default:
            debugLogQuery("CSI", csiBuffer + String(final))
        }
        _ = p  // silence unused in case of future use
    }

    private func setPrivateMode(_ params: [Int], enabled: Bool) {
        for code in params {
            switch code {
            case 7: autowrap = enabled
            case 47, 1047, 1049:
                setAlternateScreen(enabled)
            default:
                break  // 25 (cursor visibility), 2004 (bracketed paste), etc. ignored
            }
        }
    }

    private func setAlternateScreen(_ on: Bool) {
        if on {
            guard !usingAlt else { return }
            savedScreen = screen
            screen = TerminalEmulator.makeBlankScreen(rows: rows, cols: cols)
            usingAlt = true
            row = 0; col = 0; wrapNext = false
            top = 0; bottom = rows - 1
        } else {
            guard usingAlt, let restored = savedScreen else { usingAlt = false; return }
            screen = restored
            savedScreen = nil
            usingAlt = false
            wrapNext = false
            top = 0; bottom = rows - 1
            clampCursor()
        }
    }

    // MARK: - Erase / edit operations

    private func eraseInDisplay(_ mode: Int) {
        switch mode {
        case 0: // cursor → end of screen
            eraseInLine(0)
            if row + 1 < rows {
                for r in (row + 1)..<rows { screen[r] = blankLine() }
            }
        case 1: // start of screen → cursor
            if row > 0 {
                for r in 0..<row { screen[r] = blankLine() }
            }
            eraseInLine(1)
        case 2, 3: // whole screen (3 also clears scrollback)
            for r in 0..<rows { screen[r] = blankLine() }
            if mode == 3 { scrollback.removeAll(keepingCapacity: true) }
        default:
            break
        }
        wrapNext = false
    }

    private func eraseInLine(_ mode: Int) {
        switch mode {
        case 0: for c in col..<cols { screen[row][c] = blankCell() }       // cursor → end
        case 1: for c in 0...min(col, cols - 1) { screen[row][c] = blankCell() } // start → cursor
        case 2: screen[row] = blankLine()                                  // whole line
        default: break
        }
        wrapNext = false
    }

    private func insertLines(_ n: Int) {
        guard row >= top && row <= bottom else { return }
        for _ in 0..<min(n, bottom - row + 1) {
            screen.insert(blankLine(), at: row)
            screen.remove(at: bottom + 1)
        }
        wrapNext = false
    }

    private func deleteLines(_ n: Int) {
        guard row >= top && row <= bottom else { return }
        for _ in 0..<min(n, bottom - row + 1) {
            screen.remove(at: row)
            screen.insert(blankLine(), at: bottom)
        }
        wrapNext = false
    }

    private func insertBlanks(_ n: Int) {
        let count = min(n, cols - col)
        guard count > 0 else { return }
        for _ in 0..<count {
            screen[row].insert(blankCell(), at: col)
            screen[row].removeLast()
        }
        wrapNext = false
    }

    private func deleteChars(_ n: Int) {
        let count = min(n, cols - col)
        guard count > 0 else { return }
        for _ in 0..<count {
            screen[row].remove(at: col)
            screen[row].append(blankCell())
        }
        wrapNext = false
    }

    private func eraseChars(_ n: Int) {
        let end = min(col + n, cols)
        guard col < end else { return }
        for c in col..<end { screen[row][c] = blankCell() }
        wrapNext = false
    }

    // MARK: - Cursor clamping

    private func clampRow(_ r: Int) -> Int { min(max(0, r), rows - 1) }
    private func clampCol(_ c: Int) -> Int { min(max(0, c), cols - 1) }
    private func clampCursor() { row = clampRow(row); col = clampCol(col) }

    // MARK: - Glyph sanitization

    /// Pass-through: Nerd Font / Powerline glyphs (Unicode Private Use Area) are
    /// rendered as-is because the app bundles MesloLGS NF (see FontRegistrar),
    /// which provides them. Kept as a hook in case a future setting needs to
    /// strip them when a non-Nerd font is selected.
    private func sanitizedGlyph(_ ch: Character) -> Character { ch }

    // MARK: - Debug

    /// Logs terminal query sequences in DEBUG builds so we can see exactly what
    /// a remote prompt probes for (and whether we answer it). Visible in the
    /// Xcode console. No-op in release.
    private func debugLogQuery(_ kind: String, _ body: String) {
        #if DEBUG
        let escaped = body.unicodeScalars.map { $0.value < 0x20 ? "\\x\(String($0.value, radix: 16))" : String($0) }.joined()
        print("[term-query] \(kind): \(escaped)")
        #endif
    }

    // MARK: - SGR

    private func applySGR(_ rawParams: [Int]) {
        let params = rawParams.isEmpty ? [0] : rawParams
        var i = 0
        while i < params.count {
            let code = params[i]
            switch code {
            case 0: cur = Style()
            case 1: cur.bold = true
            case 2: cur.dim = true
            case 3: cur.italic = true
            case 4: cur.underline = true
            case 7: cur.reverse = true
            case 9: cur.strikethrough = true
            case 21, 22: cur.bold = false; cur.dim = false
            case 23: cur.italic = false
            case 24: cur.underline = false
            case 27: cur.reverse = false
            case 29: cur.strikethrough = false
            case 30...37: cur.fg = Self.standardColors[code - 30]
            case 39: cur.fg = nil
            case 40...47: cur.bg = Self.standardColors[code - 40]
            case 49: cur.bg = nil
            case 90...97: cur.fg = Self.brightColors[code - 90]
            case 100...107: cur.bg = Self.brightColors[code - 100]
            case 38:
                if i + 2 < params.count && params[i + 1] == 5 {
                    cur.fg = Self.color256(params[i + 2]); i += 2
                } else if i + 4 < params.count && params[i + 1] == 2 {
                    cur.fg = Color(red: Double(params[i+2])/255, green: Double(params[i+3])/255, blue: Double(params[i+4])/255); i += 4
                }
            case 48:
                if i + 2 < params.count && params[i + 1] == 5 {
                    cur.bg = Self.color256(params[i + 2]); i += 2
                } else if i + 4 < params.count && params[i + 1] == 2 {
                    cur.bg = Color(red: Double(params[i+2])/255, green: Double(params[i+3])/255, blue: Double(params[i+4])/255); i += 4
                }
            default: break
            }
            i += 1
        }
    }

    // MARK: - Colors

    private static let standardColors: [Color] = [
        Color(red: 0, green: 0, blue: 0),
        Color(red: 0.8, green: 0, blue: 0),
        Color(red: 0, green: 0.8, blue: 0),
        Color(red: 0.8, green: 0.8, blue: 0),
        Color(red: 0.3, green: 0.3, blue: 1.0),
        Color(red: 0.8, green: 0, blue: 0.8),
        Color(red: 0, green: 0.8, blue: 0.8),
        Color(red: 0.75, green: 0.75, blue: 0.75),
    ]

    private static let brightColors: [Color] = [
        Color(red: 0.5, green: 0.5, blue: 0.5),
        Color(red: 1.0, green: 0.3, blue: 0.3),
        Color(red: 0.3, green: 1.0, blue: 0.3),
        Color(red: 1.0, green: 1.0, blue: 0.3),
        Color(red: 0.5, green: 0.5, blue: 1.0),
        Color(red: 1.0, green: 0.3, blue: 1.0),
        Color(red: 0.3, green: 1.0, blue: 1.0),
        Color(red: 1.0, green: 1.0, blue: 1.0),
    ]

    private static func color256(_ index: Int) -> Color {
        switch index {
        case 0...7: return standardColors[index]
        case 8...15: return brightColors[index - 8]
        case 16...231:
            let a = index - 16
            let r = a / 36, g = (a % 36) / 6, b = a % 6
            return Color(
                red: r == 0 ? 0 : (Double(r) * 40 + 55) / 255,
                green: g == 0 ? 0 : (Double(g) * 40 + 55) / 255,
                blue: b == 0 ? 0 : (Double(b) * 40 + 55) / 255
            )
        case 232...255:
            let v = (Double(index - 232) * 10 + 8) / 255
            return Color(red: v, green: v, blue: v)
        default: return .green
        }
    }

    // MARK: - Rendering

    /// Renders scrollback + the visible screen (or just the alternate screen)
    /// into a styled AttributedString.
    func render(defaultForeground: Color,
                defaultBackground: Color,
                defaultFont: Font,
                boldFont: Font) -> AttributedString {
        var lines: [[Cell]] = usingAlt ? screen : scrollback + screen

        // Drop trailing all-blank lines so an 80x24 screen that's mostly empty
        // doesn't render a tall block of blank rows.
        while let last = lines.last, last.allSatisfy({ $0.ch == " " && $0.style.bg == nil }) {
            lines.removeLast()
        }

        var result = AttributedString()
        for (idx, line) in lines.enumerated() {
            if idx > 0 { result += AttributedString("\n") }
            result += renderLine(line,
                                 defaultForeground: defaultForeground,
                                 defaultBackground: defaultBackground,
                                 defaultFont: defaultFont,
                                 boldFont: boldFont)
        }
        return result
    }

    private func renderLine(_ line: [Cell],
                            defaultForeground: Color,
                            defaultBackground: Color,
                            defaultFont: Font,
                            boldFont: Font) -> AttributedString {
        // Trim trailing blank cells that carry no background, to avoid long
        // runs of spaces wrapping awkwardly on the narrow phone display.
        var end = line.count
        while end > 0, line[end - 1].ch == " ", line[end - 1].style.bg == nil {
            end -= 1
        }

        var result = AttributedString()
        var runText = ""
        var runStyle: Style? = nil

        func flush() {
            guard let s = runStyle, !runText.isEmpty else { return }
            result += styled(runText, style: s,
                             defaultForeground: defaultForeground,
                             defaultBackground: defaultBackground,
                             defaultFont: defaultFont, boldFont: boldFont)
            runText = ""
        }

        for i in 0..<end {
            let cell = line[i]
            if runStyle == nil || runStyle == cell.style {
                runStyle = cell.style
                runText.append(cell.ch)
            } else {
                flush()
                runStyle = cell.style
                runText.append(cell.ch)
            }
        }
        flush()
        return result
    }

    private func styled(_ text: String, style: Style,
                        defaultForeground: Color, defaultBackground: Color,
                        defaultFont: Font, boldFont: Font) -> AttributedString {
        var fg = style.fg ?? defaultForeground
        var bg = style.bg
        if style.reverse {
            let newFg = style.bg ?? defaultBackground
            let newBg = style.fg ?? defaultForeground
            fg = newFg
            bg = newBg
        }

        var attrs = AttributeContainer()
        attrs.foregroundColor = style.dim ? fg.opacity(0.6) : fg
        if let bg { attrs.backgroundColor = bg }
        attrs.font = style.bold ? boldFont : defaultFont
        if style.underline { attrs.underlineStyle = .single }
        if style.strikethrough { attrs.strikethroughStyle = .single }

        var s = AttributedString(text)
        s.mergeAttributes(attrs)
        return s
    }
}
