//
//  TerminalKeyboardView.swift
//  simplessh
//
//  Created by Miguel Jackson on 3/22/26.
//

import UIKit
import SwiftUI

/// Hidden UITextField subclass that captures keyboard input for terminal use.
/// Uses a UITextField (rather than bare UIKeyInput) because UITextField properly
/// handles all iOS text input edge cases — no double characters, reliable
/// backspace, and no ghost predictive text bar.
final class TerminalTextField: UITextField {

    /// Callback invoked for each keystroke with the raw PTY bytes to send
    var onInput: ((Data) -> Void)?

    /// Whether Ctrl modifier is active (toggled by the accessory toolbar button)
    var ctrlActive: Bool = false

    // MARK: - Setup

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        // Make invisible but functional
        alpha = 0.01  // Near-invisible but still receives touches
        tintColor = .clear
        textColor = .clear
        backgroundColor = .clear

        // Disable all text assistance
        autocorrectionType = .no
        autocapitalizationType = .none
        spellCheckingType = .no
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        keyboardType = .asciiCapable
        keyboardAppearance = .dark
        returnKeyType = .default

        // Keep a single space as placeholder content so iOS treats this as "has text"
        // This prevents edge cases with deleteBackward not firing
        text = " "

        // Build the special keys toolbar
        inputAccessoryView = buildAccessoryToolbar()
    }

    // MARK: - Hardware Keyboard Special Keys

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            guard let key = press.key else { continue }

            // Ctrl+letter from hardware keyboard
            if key.modifierFlags.contains(.control),
               let char = key.characters.uppercased().first,
               let ascii = char.asciiValue,
               ascii >= 65, ascii <= 90 {
                onInput?(Data([UInt8(ascii - 64)]))
                handled = true
                continue
            }

            if let sequence = ansiSequence(for: key.keyCode) {
                onInput?(sequence)
                handled = true
            }
        }
        if !handled {
            super.pressesBegan(presses, with: event)
        }
    }

    /// Maps hardware key codes to ANSI/VT100 escape sequences
    private func ansiSequence(for keyCode: UIKeyboardHIDUsage) -> Data? {
        switch keyCode {
        case .keyboardUpArrow:           return Data("\u{1B}[A".utf8)
        case .keyboardDownArrow:         return Data("\u{1B}[B".utf8)
        case .keyboardRightArrow:        return Data("\u{1B}[C".utf8)
        case .keyboardLeftArrow:         return Data("\u{1B}[D".utf8)
        case .keyboardEscape:            return Data([0x1B])
        case .keyboardTab:               return Data([0x09])
        case .keyboardDeleteOrBackspace: return Data([0x7F])
        case .keyboardHome:              return Data("\u{1B}[H".utf8)
        case .keyboardEnd:               return Data("\u{1B}[F".utf8)
        case .keyboardPageUp:            return Data("\u{1B}[5~".utf8)
        case .keyboardPageDown:          return Data("\u{1B}[6~".utf8)
        case .keyboardDeleteForward:     return Data("\u{1B}[3~".utf8)
        case .keyboardF1:               return Data("\u{1B}OP".utf8)
        case .keyboardF2:               return Data("\u{1B}OQ".utf8)
        case .keyboardF3:               return Data("\u{1B}OR".utf8)
        case .keyboardF4:               return Data("\u{1B}OS".utf8)
        case .keyboardF5:               return Data("\u{1B}[15~".utf8)
        case .keyboardF6:               return Data("\u{1B}[17~".utf8)
        case .keyboardF7:               return Data("\u{1B}[18~".utf8)
        case .keyboardF8:               return Data("\u{1B}[19~".utf8)
        case .keyboardF9:               return Data("\u{1B}[20~".utf8)
        case .keyboardF10:              return Data("\u{1B}[21~".utf8)
        case .keyboardF11:              return Data("\u{1B}[23~".utf8)
        case .keyboardF12:              return Data("\u{1B}[24~".utf8)
        default:                         return nil
        }
    }

    // MARK: - Input Accessory View (Special Keys Toolbar)

    weak var ctrlButton: UIButton?

    private func buildAccessoryToolbar() -> UIToolbar {
        let toolbar = UIToolbar()
        toolbar.barStyle = .black
        toolbar.isTranslucent = true
        toolbar.sizeToFit()

        let keys: [(String, Data?)] = [
            ("esc", Data([0x1B])),
            ("tab", Data([0x09])),
            ("ctrl", nil), // special toggle
            ("↑", Data("\u{1B}[A".utf8)),
            ("↓", Data("\u{1B}[B".utf8)),
            ("←", Data("\u{1B}[D".utf8)),
            ("→", Data("\u{1B}[C".utf8)),
            ("|", Data("|".utf8)),
            ("~", Data("~".utf8)),
            ("-", Data("-".utf8)),
            ("/", Data("/".utf8)),
        ]

        var items: [UIBarButtonItem] = []

        for (index, key) in keys.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(key.0, for: .normal)
            button.titleLabel?.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
            button.setTitleColor(.white, for: .normal)
            button.tag = index

            if key.0 == "ctrl" {
                button.addTarget(self, action: #selector(ctrlTapped(_:)), for: .touchUpInside)
                self.ctrlButton = button
            } else {
                button.addTarget(self, action: #selector(accessoryKeyTapped(_:)), for: .touchUpInside)
            }

            let barItem = UIBarButtonItem(customView: button)
            items.append(barItem)

            if index < keys.count - 1 {
                items.append(UIBarButtonItem(systemItem: .flexibleSpace))
            }
        }

        toolbar.items = items
        return toolbar
    }

    private var accessoryKeyData: [Int: Data] {
        [
            0: Data([0x1B]),           // esc
            1: Data([0x09]),           // tab
            3: Data("\u{1B}[A".utf8),  // ↑
            4: Data("\u{1B}[B".utf8),  // ↓
            5: Data("\u{1B}[D".utf8),  // ←
            6: Data("\u{1B}[C".utf8),  // →
            7: Data("|".utf8),         // |
            8: Data("~".utf8),         // ~
            9: Data("-".utf8),         // -
            10: Data("/".utf8),        // /
        ]
    }

    @objc private func accessoryKeyTapped(_ sender: UIButton) {
        if let data = accessoryKeyData[sender.tag] {
            onInput?(data)
        }
    }

    @objc private func ctrlTapped(_ sender: UIButton) {
        ctrlActive.toggle()
        sender.setTitleColor(ctrlActive ? .systemGreen : .white, for: .normal)
    }
}

// MARK: - SwiftUI Bridge

/// UIViewRepresentable that bridges `TerminalTextField` into SwiftUI.
/// Uses a UITextFieldDelegate to intercept every keystroke, send it to the PTY,
/// and prevent any text from actually accumulating in the field.
struct TerminalKeyboardCapture: UIViewRepresentable {
    /// Callback invoked with raw PTY bytes for each keystroke
    let onInput: (Data) -> Void

    /// Whether the terminal is connected (keyboard only shows when connected)
    let isConnected: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(onInput: onInput)
    }

    func makeUIView(context: Context) -> TerminalTextField {
        let field = TerminalTextField()
        field.onInput = onInput
        field.delegate = context.coordinator
        context.coordinator.terminalField = field
        return field
    }

    func updateUIView(_ uiView: TerminalTextField, context: Context) {
        context.coordinator.onInput = onInput
        uiView.onInput = onInput
        if isConnected && !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isConnected && uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    /// Coordinator acts as UITextFieldDelegate to intercept every character change
    class Coordinator: NSObject, UITextFieldDelegate {
        var onInput: (Data) -> Void
        weak var terminalField: TerminalTextField?

        init(onInput: @escaping (Data) -> Void) {
            self.onInput = onInput
        }

        /// Intercepts every text change before it happens.
        /// Returns false to prevent text from accumulating — we handle it ourselves.
        func textField(_ textField: UITextField,
                       shouldChangeCharactersIn range: NSRange,
                       replacementString string: String) -> Bool {

            let field = terminalField

            if string.isEmpty && range.length > 0 {
                // Backspace: replacement is empty, range has length
                onInput(Data([0x7F]))
            } else if !string.isEmpty {
                // Check for Ctrl modifier
                if let field, field.ctrlActive {
                    field.ctrlActive = false
                    field.ctrlButton?.setTitleColor(.white, for: .normal)
                    if let char = string.uppercased().first,
                       let ascii = char.asciiValue,
                       ascii >= 65, ascii <= 90 {
                        onInput(Data([UInt8(ascii - 64)]))
                        resetField(textField)
                        return false
                    }
                }

                // Return key sends \r (carriage return for PTY)
                if string == "\n" {
                    onInput(Data([0x0D]))
                } else if let data = string.data(using: .utf8) {
                    onInput(data)
                }
            }

            // Always reset the field to a single space — prevents accumulation
            // and keeps iOS happy (thinks there's text to delete)
            resetField(textField)
            return false
        }

        /// Resets the text field to a single space with cursor at the end
        private func resetField(_ textField: UITextField) {
            textField.text = " "
            // Move cursor to end so next backspace has a character to "delete"
            let end = textField.endOfDocument
            textField.selectedTextRange = textField.textRange(from: end, to: end)
        }
    }
}
