import SwiftUI
#if os(macOS)
    import AppKit
#else
    import GameController
    import UIKit
#endif

/// A shortcut's keys as caps; while recording, a prompt for the next key
/// combination. Click it to record: the combination is saved at once, Esc
/// cancels, and Delete clears when `clear` is given (otherwise Delete is
/// recorded like any other key).
struct ShortcutRecorder: View {
    let steps: [String]
    @Binding var isRecording: Bool
    let record: (String) -> Void
    var clear: (() -> Void)?

    /// Whether a key press can be recorded here: always on the Mac, on iOS
    /// only with a hardware keyboard.
    @MainActor static var canRecord: Bool {
        #if os(macOS)
            true
        #else
            GCKeyboard.coalesced != nil
        #endif
    }

    var body: some View {
        Button {
            isRecording.toggle()
        } label: {
            if isRecording {
                Text("Type Shortcut", bundle: .module)
                    .font(.callout)
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.tint))
            } else {
                ShortcutCaps(steps: steps)
            }
        }
        .buttonStyle(.plain)
        .help(hint)
        .background(KeyRecorder(
            active: isRecording,
            record: { step in
                isRecording = false
                record(step)
            },
            cancel: { isRecording = false },
            clear: clear.map { clear in { isRecording = false; clear() } }
        ))
        .onDisappear { isRecording = false }
    }

    private var hint: Text {
        if !isRecording { return Text("Click to record a new shortcut", bundle: .module) }
        if clear == nil { return Text("Press the new keys; Esc cancels", bundle: .module) }
        return Text("Press the new keys; Esc cancels, Delete removes the shortcut", bundle: .module)
    }
}

/// A shortcut's keys as caps, with "then" between the steps of a sequence.
struct ShortcutCaps: View {
    let steps: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.offset) { offset, step in
                if offset > 0 { Text(KeybindingNames.then).font(.caption).foregroundStyle(.secondary) }
                KeyCaps(text: KeybindingNames.step(step))
            }
        }
    }
}

/// What a recorder does with a key press: plain Esc cancels, plain Delete
/// clears when the recorder can, anything else is the new step.
private enum RecordedPress {
    case step(String)
    case cancel
    case clear
    /// A modifier on its own, or a key Ghostty has no name for: keep waiting.
    case ignore

    init(mods: [String], key: String?, canClear: Bool) {
        guard let key else { self = .ignore; return }
        if mods.isEmpty, key == "escape" { self = .cancel; return }
        if mods.isEmpty, canClear, key == "backspace" || key == "delete" { self = .clear; return }
        self = .step((mods.sorted() + [key]).joined(separator: "+"))
    }
}

#if os(macOS)
    /// Captures the next key press, with its modifiers, while `active`. A
    /// local monitor sees the press before the menu bar, so ⌘ shortcuts the
    /// app's menus use can be recorded too.
    private struct KeyRecorder: NSViewRepresentable {
        let active: Bool
        let record: (String) -> Void
        let cancel: () -> Void
        let clear: (() -> Void)?

        final class Coordinator {
            var monitor: Any?
            var handle: ((RecordedPress) -> Void)?
            var canClear = false
            deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
        }

        func makeCoordinator() -> Coordinator { Coordinator() }
        func makeNSView(context _: Context) -> NSView { NSView() }

        func updateNSView(_: NSView, context: Context) {
            let coordinator = context.coordinator
            coordinator.canClear = clear != nil
            coordinator.handle = { press in
                switch press {
                case let .step(step): record(step)
                case .cancel: cancel()
                case .clear: clear?()
                case .ignore: break
                }
            }
            if active, coordinator.monitor == nil {
                coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak coordinator] event in
                    guard let coordinator else { return event }
                    let press = RecordedPress(mods: Self.mods(event.modifierFlags), key: Self.key(for: event), canClear: coordinator.canClear)
                    if case .ignore = press { return nil }
                    if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
                    coordinator.monitor = nil
                    coordinator.handle?(press)
                    return nil
                }
            } else if !active, let monitor = coordinator.monitor {
                NSEvent.removeMonitor(monitor)
                coordinator.monitor = nil
            }
        }

        private static let specialKeys: [UInt16: String] = [
            36: "enter", 48: "tab", 49: "space", 51: "backspace", 53: "escape", 117: "delete",
            115: "home", 119: "end", 116: "page_up", 121: "page_down",
            123: "arrow_left", 124: "arrow_right", 125: "arrow_down", 126: "arrow_up",
            122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6", 98: "f7", 100: "f8",
            101: "f9", 109: "f10", 103: "f11", 111: "f12",
        ]

        private static func mods(_ flags: NSEvent.ModifierFlags) -> [String] {
            var mods: [String] = []
            if flags.contains(.control) { mods.append("ctrl") }
            if flags.contains(.option) { mods.append("alt") }
            if flags.contains(.shift) { mods.append("shift") }
            if flags.contains(.command) { mods.append("super") }
            return mods
        }

        private static func key(for event: NSEvent) -> String? {
            if let special = specialKeys[event.keyCode] { return special }
            guard let character = event.characters(byApplyingModifiers: [])?.lowercased(), character.unicodeScalars.count == 1 else { return nil }
            return character
        }
    }
#else
    /// Captures the next key press, with its modifiers, while `active`, from
    /// a hardware keyboard.
    private struct KeyRecorder: UIViewRepresentable {
        let active: Bool
        let record: (String) -> Void
        let cancel: () -> Void
        let clear: (() -> Void)?

        final class Catcher: UIView {
            var handle: ((RecordedPress) -> Void)?
            var canClear = false
            var cancelled: (() -> Void)?
            /// Mirrors `active` so a queued focus grab dies once recording ended.
            var armed = false
            override var canBecomeFirstResponder: Bool { true }

            override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
                for press in presses {
                    guard let key = press.key else { continue }
                    let recorded = RecordedPress(mods: KeyRecorder.mods(key.modifierFlags), key: KeyRecorder.key(for: key), canClear: canClear)
                    if case .ignore = recorded { continue }
                    armed = false
                    handle?(recorded)
                    return
                }
            }

            override func resignFirstResponder() -> Bool {
                let resigned = super.resignFirstResponder()
                // A tap into another field, or another recorder starting,
                // ends this recording; the cancel checks it is still this one.
                if resigned, armed { DispatchQueue.main.async { self.cancelled?() } }
                return resigned
            }
        }

        func makeUIView(context _: Context) -> Catcher { Catcher() }

        func updateUIView(_ view: Catcher, context _: Context) {
            view.canClear = clear != nil
            view.cancelled = cancel
            view.handle = { press in
                switch press {
                case let .step(step): record(step)
                case .cancel: cancel()
                case .clear: clear?()
                case .ignore: break
                }
            }
            view.armed = active
            if active, !view.isFirstResponder {
                DispatchQueue.main.async { if view.armed { view.becomeFirstResponder() } }
            } else if !active, view.isFirstResponder {
                _ = view.resignFirstResponder()
            }
        }

        private static let specialKeys: [UIKeyboardHIDUsage: String] = [
            .keyboardReturnOrEnter: "enter", .keyboardTab: "tab", .keyboardSpacebar: "space",
            .keyboardDeleteOrBackspace: "backspace", .keyboardEscape: "escape", .keyboardDeleteForward: "delete",
            .keyboardHome: "home", .keyboardEnd: "end", .keyboardPageUp: "page_up", .keyboardPageDown: "page_down",
            .keyboardLeftArrow: "arrow_left", .keyboardRightArrow: "arrow_right",
            .keyboardDownArrow: "arrow_down", .keyboardUpArrow: "arrow_up",
            .keyboardF1: "f1", .keyboardF2: "f2", .keyboardF3: "f3", .keyboardF4: "f4", .keyboardF5: "f5",
            .keyboardF6: "f6", .keyboardF7: "f7", .keyboardF8: "f8", .keyboardF9: "f9", .keyboardF10: "f10",
            .keyboardF11: "f11", .keyboardF12: "f12",
        ]

        /// The unshifted character of the keys whose shifted one differs.
        private static let unshifted: [UIKeyboardHIDUsage: String] = [
            .keyboard1: "1", .keyboard2: "2", .keyboard3: "3", .keyboard4: "4", .keyboard5: "5",
            .keyboard6: "6", .keyboard7: "7", .keyboard8: "8", .keyboard9: "9", .keyboard0: "0",
            .keyboardHyphen: "-", .keyboardEqualSign: "=", .keyboardOpenBracket: "[", .keyboardCloseBracket: "]",
            .keyboardBackslash: "\\", .keyboardSemicolon: ";", .keyboardQuote: "'", .keyboardGraveAccentAndTilde: "`",
            .keyboardComma: ",", .keyboardPeriod: ".", .keyboardSlash: "/",
        ]

        fileprivate static func mods(_ flags: UIKeyModifierFlags) -> [String] {
            var mods: [String] = []
            if flags.contains(.control) { mods.append("ctrl") }
            if flags.contains(.alternate) { mods.append("alt") }
            if flags.contains(.shift) { mods.append("shift") }
            if flags.contains(.command) { mods.append("super") }
            return mods
        }

        fileprivate static func key(for key: UIKey) -> String? {
            if let special = specialKeys[key.keyCode] { return special }
            if key.modifierFlags.contains(.shift) || key.modifierFlags.contains(.alternate), let plain = unshifted[key.keyCode] { return plain }
            let character = key.charactersIgnoringModifiers.lowercased()
            return character.unicodeScalars.count == 1 ? character : nil
        }
    }
#endif
