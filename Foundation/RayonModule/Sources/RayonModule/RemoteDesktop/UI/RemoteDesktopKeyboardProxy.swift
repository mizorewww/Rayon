//
//  RemoteDesktopKeyboardProxy.swift
//  RayonModule
//
//  The text input the iOS remote-desktop canvas brings the software
//  keyboard up for.
//

#if canImport(UIKit)
    import UIKit

    /// A text view out of sight in the canvas's corner, so the system's
    /// input methods compose in it (Pinyin, Kana, Hangul) as in any text
    /// field: what they commit goes to the host as text, and the view
    /// empties again. Keys that type nothing, and keys under Ctrl, Option
    /// or Command, go to the host as keys.
    final class RemoteDesktopKeyboardProxy: UITextView, UITextViewDelegate {
        weak var canvas: RemoteDesktopCanvasView?
        /// Hardware presses sent to the host as keys; the input method
        /// never sees them.
        private var keyPresses: Set<UIPress> = []

        init() {
            super.init(frame: CGRect(x: 0, y: 0, width: 1, height: 1), textContainer: nil)
            delegate = self
            backgroundColor = .clear
            textColor = .clear
            tintColor = .clear
            isScrollEnabled = false
            autocorrectionType = .no
            autocapitalizationType = .none
            spellCheckingType = .no
            smartQuotesType = .no
            smartDashesType = .no
            smartInsertDeleteType = .no
            inlinePredictionType = .no
            if #available(iOS 18.0, *) { writingToolsBehavior = .none }
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) { nil }

        #if os(iOS) && !targetEnvironment(macCatalyst)
            override var editingInteractionConfiguration: UIEditingInteractionConfiguration { .none }
        #endif

        // MARK: Hardware keys

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            var toInputMethod = Set<UIPress>()
            for press in presses {
                if sendsAsKey(press), canvas?.hardwareKey(press, isDown: true) == true {
                    keyPresses.insert(press)
                } else {
                    toInputMethod.insert(press)
                }
            }
            if !toInputMethod.isEmpty { super.pressesBegan(toInputMethod, with: event) }
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            let toInputMethod = release(presses)
            if !toInputMethod.isEmpty { super.pressesEnded(toInputMethod, with: event) }
        }

        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            let toInputMethod = release(presses)
            if !toInputMethod.isEmpty { super.pressesCancelled(toInputMethod, with: event) }
        }

        /// Lets go of the presses sent as keys; returns the others.
        private func release(_ presses: Set<UIPress>) -> Set<UIPress> {
            presses.filter { press in
                guard keyPresses.remove(press) != nil else { return true }
                _ = canvas?.hardwareKey(press, isDown: false)
                return false
            }
        }

        /// A press is the input method's while it composes (its arrows pick,
        /// its Return commits) and when it types text by itself; any other
        /// is a key for the host.
        private func sendsAsKey(_ press: UIPress) -> Bool {
            guard let key = press.key, markedTextRange == nil else { return false }
            if !key.modifierFlags.isDisjoint(with: [.control, .alternate, .command]) { return true }
            guard let scalar = key.characters.unicodeScalars.first, scalar.value >= 0x20, scalar.value != 0x7F else { return true }
            return VNCKeySyms.keySym(forCharacter: key.characters) == nil
        }

        /// A key sent to the host is still a key to the text system, which
        /// types it here too: Return, Backspace or a paste. That echo is
        /// dropped. Modifiers type nothing, so a held Shift drops nothing.
        private var echoesKey: Bool {
            keyPresses.contains { press in
                guard let usage = press.key?.keyCode.rawValue else { return false }
                return usage != 0x39 && !(0xE0 ... 0xE7).contains(usage)
            }
        }

        // MARK: Text

        func textViewDidChange(_: UITextView) {
            guard markedTextRange == nil, !text.isEmpty else { return }
            let typed = text ?? ""
            text = ""
            if !echoesKey { canvas?.insertTyped(typed) }
        }

        /// Return goes as the key, so the host sees Return, not a line feed.
        override func insertText(_ text: String) {
            guard markedTextRange == nil, text == "\n" else { return super.insertText(text) }
            if !echoesKey { canvas?.insertTyped(text) }
        }

        /// The view is empty unless an input method composes in it: a
        /// backspace on nothing is one for the host.
        override func deleteBackward() {
            guard markedTextRange == nil, text.isEmpty else { return super.deleteBackward() }
            if !echoesKey { canvas?.deleteTypedBackward() }
        }
    }
#endif
