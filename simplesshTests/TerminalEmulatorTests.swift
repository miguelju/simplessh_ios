//
//  TerminalEmulatorTests.swift
//  simplesshTests
//
//  Feeds byte sequences to TerminalEmulator and asserts on the grid, cursor,
//  scrollback, alternate screen and query replies.
//

import Testing
import SwiftUI
@testable import simplessh

struct TerminalEmulatorTests {

    private let esc = "\u{1B}"

    private func make(cols: Int = 10, rows: Int = 4) -> TerminalEmulator {
        TerminalEmulator(cols: cols, rows: rows)
    }

    // MARK: - Plain text and C0 controls

    @Test func printsTextAndAdvancesCursor() {
        let t = make()
        t.feed("hi")
        #expect(t.lineText(0) == "hi")
        #expect(t.cursorRow == 0)
        #expect(t.cursorCol == 2)
    }

    @Test func crlfStartsANewLine() {
        let t = make()
        t.feed("ab\r\ncd")
        #expect(t.screenText == ["ab", "cd", "", ""])
        #expect(t.cursorRow == 1)
        #expect(t.cursorCol == 2)
    }

    @Test func bareLineFeedKeepsTheColumn() {
        let t = make()
        t.feed("ab\ncd")
        #expect(t.lineText(0) == "ab")
        #expect(t.lineText(1) == "  cd")
        #expect(t.cursorCol == 4)
    }

    @Test func carriageReturnOverwritesFromColumnZero() {
        let t = make()
        t.feed("abc\rX")
        #expect(t.lineText(0) == "Xbc")
    }

    @Test func backspaceMovesLeftWithoutErasing() {
        let t = make()
        t.feed("abc\u{08}")
        #expect(t.cursorCol == 2)
        #expect(t.lineText(0) == "abc")
        t.feed("\u{08}\u{08}\u{08}")
        #expect(t.cursorCol == 0)
    }

    @Test func tabAdvancesToTheNextStop() {
        let t = make(cols: 20)
        t.feed("a\tb")
        #expect(t.lineText(0) == "a       b")
        #expect(t.cursorCol == 9)
    }

    @Test func bellAndOtherControlsAreIgnored() {
        let t = make()
        t.feed("a\u{07}b\u{00}c\u{01}")
        #expect(t.lineText(0) == "abc")
    }

    @Test func unicodeAndPrivateUseGlyphsPassThrough() {
        let t = make()
        t.feed("λ→\u{E0B0}")
        #expect(t.lineText(0) == "λ→\u{E0B0}")
        #expect(t.cursorCol == 3)
    }

    @Test func charsetDesignatorIsConsumed() {
        let t = make()
        t.feed("\(esc)(Bx\(esc))0y")
        #expect(t.lineText(0) == "xy")
    }

    // MARK: - Wrapping and scrolling

    @Test func autowrapDefersUntilTheNextCharacter() {
        let t = make(cols: 4)
        t.feed("abcd")
        #expect(t.cursorRow == 0)
        #expect(t.cursorCol == 3)
        t.feed("e")
        #expect(t.lineText(0) == "abcd")
        #expect(t.lineText(1) == "e")
        #expect(t.cursorRow == 1)
        #expect(t.cursorCol == 1)
    }

    @Test func carriageReturnCancelsPendingWrap() {
        let t = make(cols: 4)
        t.feed("abcd\r\nx")
        #expect(t.screenText == ["abcd", "x", "", ""])
    }

    @Test func autowrapCanBeDisabled() {
        let t = make(cols: 4)
        t.feed("\(esc)[?7labcdef")
        #expect(t.lineText(0) == "abcf")
        #expect(t.cursorRow == 0)
    }

    @Test func scrollingAtTheBottomMovesLinesIntoScrollback() {
        let t = make(rows: 2)
        t.feed("1\r\n2\r\n3")
        #expect(t.screenText == ["2", "3"])
        #expect(t.scrollbackLineCount == 1)
        #expect(t.scrollbackLineText(0) == "1")
    }

    @Test func scrollbackIsBoundedToTwoThousandLines() {
        let t = make(cols: 6, rows: 1)
        for i in 0...2100 { t.feed("\(i)\r\n") }
        #expect(t.scrollbackLineCount == 2000)
        #expect(t.scrollbackLineText(0) == "101")
        #expect(t.scrollbackLineText(1999) == "2100")
    }

    // MARK: - Cursor movement

    @Test func csiCursorMovesAndClamps() {
        let t = make(cols: 80, rows: 24)
        t.feed("\(esc)[5;10H")
        #expect(t.cursorRow == 4); #expect(t.cursorCol == 9)
        t.feed("\(esc)[2A"); #expect(t.cursorRow == 2)
        t.feed("\(esc)[3B"); #expect(t.cursorRow == 5)
        t.feed("\(esc)[4C"); #expect(t.cursorCol == 13)
        t.feed("\(esc)[2D"); #expect(t.cursorCol == 11)
        t.feed("\(esc)[G");  #expect(t.cursorCol == 0)
        t.feed("\(esc)[7d"); #expect(t.cursorRow == 6)
        t.feed("\(esc)[3;3f"); #expect(t.cursorRow == 2); #expect(t.cursorCol == 2)
        t.feed("\(esc)[H");  #expect(t.cursorRow == 0); #expect(t.cursorCol == 0)
        t.feed("\(esc)[99;99H"); #expect(t.cursorRow == 23); #expect(t.cursorCol == 79)
        t.feed("\(esc)[50A\(esc)[99D"); #expect(t.cursorRow == 0); #expect(t.cursorCol == 0)
    }

    @Test func cursorNextAndPreviousLineResetTheColumn() {
        let t = make(cols: 80, rows: 24)
        t.feed("\(esc)[5;10H\(esc)[2E")
        #expect(t.cursorRow == 6); #expect(t.cursorCol == 0)
        t.feed("\(esc)[3;3H\(esc)[F")
        #expect(t.cursorRow == 1); #expect(t.cursorCol == 0)
    }

    @Test func saveAndRestoreCursorKeepsPositionAndStyle() {
        let t = make(cols: 20, rows: 5)
        t.feed("\(esc)[3;4H\(esc)[1m\(esc)7")     // DECSC with bold on
        t.feed("\(esc)[0m\(esc)[H")
        t.feed("\(esc)8x")                          // DECRC, then print
        #expect(t.cursorRow == 2); #expect(t.cursorCol == 4)
        #expect(t.cell(row: 2, col: 3).style.bold)
        t.feed("\(esc)[s\(esc)[H\(esc)[uy")        // CSI s / CSI u pair
        #expect(t.cell(row: 2, col: 4).ch == "y")
    }

    // MARK: - SGR

    @Test func sgrSetsAndClearsAttributes() {
        let t = make(cols: 20)
        t.feed("\(esc)[1;3;4;7;9mA\(esc)[0mB")
        let a = t.cell(row: 0, col: 0).style
        #expect(a.bold && a.italic && a.underline && a.reverse && a.strikethrough)
        #expect(t.cell(row: 0, col: 1).style == TerminalEmulator.Style())
        t.feed("\(esc)[1;2m\(esc)[22mC")
        let c = t.cell(row: 0, col: 2).style
        #expect(!c.bold && !c.dim)
    }

    @Test func sgrColoursCoverAllThreeForms() {
        let t = make(cols: 20)
        t.feed("\(esc)[31;44mA\(esc)[39;49mB\(esc)[38;5;196mC\(esc)[48;2;10;20;30mD")
        #expect(t.cell(row: 0, col: 0).style.fg != nil)
        #expect(t.cell(row: 0, col: 0).style.bg != nil)
        #expect(t.cell(row: 0, col: 1).style.fg == nil)
        #expect(t.cell(row: 0, col: 1).style.bg == nil)
        #expect(t.cell(row: 0, col: 2).style.fg != nil)
        #expect(t.cell(row: 0, col: 3).style.bg == Color(red: 10.0 / 255, green: 20.0 / 255, blue: 30.0 / 255))
    }

    @Test func erasedCellsKeepTheCurrentBackground() {
        let t = make()
        t.feed("\(esc)[44m\(esc)[2J")
        #expect(t.cell(row: 3, col: 9).style.bg != nil)
        #expect(!t.cell(row: 3, col: 9).style.bold)
    }

    // MARK: - Erase and edit

    @Test func eraseInLine() {
        let t = make()
        t.feed("abcdef\(esc)[3G\(esc)[K")
        #expect(t.lineText(0) == "ab")
        t.feed("\rabcdef\(esc)[3G\(esc)[1K")
        #expect(t.lineText(0) == "   def")
        t.feed("\(esc)[2K")
        #expect(t.lineText(0) == "")
    }

    @Test func eraseInDisplay() {
        let t = make(rows: 3)
        t.feed("a\r\nb\r\nc\(esc)[2;1H\(esc)[J")
        #expect(t.screenText == ["a", "", ""])
        t.feed("\(esc)[Ha\r\nabc\r\nc\(esc)[2;2H\(esc)[1J")
        #expect(t.screenText == ["", "  c", "c"])
        t.feed("\(esc)[2J")
        #expect(t.screenText == ["", "", ""])
        #expect(t.cursorRow == 1)
    }

    @Test func eraseModeThreeClearsScrollback() {
        let t = make(rows: 2)
        t.feed("1\r\n2\r\n3")
        #expect(t.scrollbackLineCount == 1)
        t.feed("\(esc)[3J")
        #expect(t.scrollbackLineCount == 0)
    }

    @Test func insertAndDeleteLines() {
        let t = make()
        t.feed("a\r\nb\r\nc\r\nd\(esc)[2;1H\(esc)[L")
        #expect(t.screenText == ["a", "", "b", "c"])
        t.feed("\(esc)[2M")
        #expect(t.screenText == ["a", "c", "", ""])
    }

    @Test func insertDeleteAndEraseCharacters() {
        let t = make()
        t.feed("abcdef\(esc)[2G\(esc)[2@")
        #expect(t.lineText(0) == "a  bcdef")
        t.feed("\(esc)[2P")
        #expect(t.lineText(0) == "abcdef")
        t.feed("\(esc)[2X")
        #expect(t.lineText(0) == "a  def")
    }

    // MARK: - Scroll region

    @Test func decstbmScrollsOnlyTheRegion() {
        let t = make(rows: 5)
        t.feed("top\(esc)[5;1Hbottom\(esc)[2;4r")
        #expect(t.scrollTop == 1); #expect(t.scrollBottom == 3)
        #expect(t.cursorRow == 1); #expect(t.cursorCol == 0)
        t.feed("1\r\n2\r\n3\r\n4")
        #expect(t.screenText == ["top", "2", "3", "4", "bottom"])
        #expect(t.scrollbackLineCount == 0)
        t.feed("\(esc)[r")
        #expect(t.scrollTop == 0); #expect(t.scrollBottom == 4)
    }

    @Test func reverseIndexScrollsDownAtTheTop() {
        let t = make(rows: 3)
        t.feed("a\r\nb\r\nc\(esc)[H\(esc)M")
        #expect(t.screenText == ["", "a", "b"])
    }

    @Test func indexAndNextLine() {
        let t = make(rows: 3)
        t.feed("ab\(esc)D")           // IND: down, same column
        #expect(t.cursorRow == 1); #expect(t.cursorCol == 2)
        t.feed("\(esc)E")             // NEL: down, column 0
        #expect(t.cursorRow == 2); #expect(t.cursorCol == 0)
    }

    // MARK: - Alternate screen

    @Test func alternateScreenIsBlankAndRestoresMain() {
        let t = make()
        t.feed("main\(esc)[?1049h")
        #expect(t.isAlternateScreenActive)
        #expect(t.screenText == ["", "", "", ""])
        #expect(t.cursorRow == 0); #expect(t.cursorCol == 0)
        t.feed("alt")
        #expect(t.lineText(0) == "alt")
        t.feed("\(esc)[?1049l")
        #expect(!t.isAlternateScreenActive)
        #expect(t.lineText(0) == "main")
    }

    @Test func alternateScreenDoesNotFeedScrollback() {
        let t = make(rows: 2)
        t.feed("\(esc)[?47h1\r\n2\r\n3")
        #expect(t.scrollbackLineCount == 0)
        t.feed("\(esc)[?47l")
        #expect(t.scrollbackLineCount == 0)
    }

    @Test func risResetsEverything() {
        let t = make(rows: 2)
        t.feed("1\r\n2\r\n3\(esc)[?1049h\(esc)[1mx\(esc)c")
        #expect(!t.isAlternateScreenActive)
        #expect(t.screenText == ["", ""])
        #expect(t.scrollbackLineCount == 0)
        #expect(t.cursorRow == 0); #expect(t.cursorCol == 0)
        t.feed("y")
        #expect(!t.cell(row: 0, col: 0).style.bold)
    }

    // MARK: - Query replies

    @Test func deviceStatusReportReplies() {
        let t = make(cols: 80, rows: 24)
        #expect(t.drainReply() == nil)
        t.feed("\(esc)[3;5H\(esc)[6n")
        #expect(t.drainReply() == "\(esc)[3;5R")
        #expect(t.drainReply() == nil)
        t.feed("\(esc)[5n")
        #expect(t.drainReply() == "\(esc)[0n")
        t.feed("\(esc)[?6n")
        #expect(t.drainReply() == "\(esc)[?3;5R")
    }

    @Test func deviceAttributesReplies() {
        let t = make()
        t.feed("\(esc)[c")
        #expect(t.drainReply() == "\(esc)[?1;2c")
        t.feed("\(esc)[>c")
        #expect(t.drainReply() == "\(esc)[>0;10;0c")
    }

    @Test func windowSizeReportUsesTheGrid() {
        let t = make(cols: 46, rows: 30)
        t.feed("\(esc)[18t")
        #expect(t.drainReply() == "\(esc)[8;30;46t")
    }

    @Test func oscColourQueriesAreAnsweredAndTitlesSwallowed() {
        let t = make()
        t.feed("\(esc)]11;?\u{07}")
        #expect(t.drainReply() == "\(esc)]11;rgb:0000/0000/0000\u{07}")
        t.feed("\(esc)]10;?\(esc)\\")                     // ST-terminated
        #expect(t.drainReply() == "\(esc)]10;rgb:ffff/ffff/ffff\u{07}")
        t.feed("\(esc)]0;window title\u{07}x")
        #expect(t.lineText(0) == "x")
        #expect(t.drainReply() == nil)
    }

    @Test func repliesAccumulateUntilDrained() {
        let t = make()
        t.feed("\(esc)[5n\(esc)[c")
        #expect(t.drainReply() == "\(esc)[0n\(esc)[?1;2c")
    }

    // MARK: - Sequences split across feeds

    @Test func sequencesSplitAcrossFeedsAreReassembled() {
        let t = make()
        t.feed("ab")
        t.feed("\(esc)[")
        t.feed("1;1H")
        #expect(t.cursorRow == 0); #expect(t.cursorCol == 0)
        t.feed("\(esc)]0;ti")
        t.feed("tle\u{07}Z")
        #expect(t.lineText(0) == "Zb")
        t.feed("\(esc)")
        t.feed("[3")
        t.feed("1mQ")
        #expect(t.cell(row: 0, col: 1).style.fg != nil)
        #expect(t.lineText(0) == "ZQ")
    }

    @Test func crlfSplitAcrossFeedsStillBreaksTheLine() {
        let t = make()
        t.feed("a\r")
        t.feed("\nb")
        #expect(t.screenText == ["a", "b", "", ""])
    }

    // MARK: - Rendering

    @Test func renderJoinsScrollbackAndScreenAndDropsTrailingBlanks() {
        let t = make(rows: 2)
        t.feed("1\r\n2\r\n3")
        let rendered = t.render(defaultForeground: .white, defaultBackground: .black,
                                defaultFont: .system(size: 12), boldFont: .system(size: 12).bold())
        #expect(String(rendered.characters) == "1\n2\n3")
    }

    @Test func renderUsesTheBoldFontForBoldRuns() {
        let t = make(cols: 20)
        let plain = Font.system(size: 12)
        let bold = Font.system(size: 12).bold()
        t.feed("a\(esc)[1mb\(esc)[0mc")
        let rendered = t.render(defaultForeground: .white, defaultBackground: .black,
                                defaultFont: plain, boldFont: bold)
        let fonts = rendered.runs.map { $0.font }
        #expect(fonts == [plain, bold, plain])
    }

    @Test func renderShowsOnlyTheAlternateScreenWhileActive() {
        let t = make(rows: 2)
        t.feed("1\r\n2\r\n3\(esc)[?1049halt")
        let rendered = t.render(defaultForeground: .white, defaultBackground: .black,
                                defaultFont: .system(size: 12), boldFont: .system(size: 12).bold())
        #expect(String(rendered.characters) == "alt")
    }
}
