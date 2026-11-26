#if os(macOS)
    import AppKit
#else
    import UIKit
#endif
import BlossomColorPicker
import SwiftUI

/// A color setting: the BlossomColorPicker swatch, its hex value, and the
/// named values the setting also takes (Ghostty's "cell-foreground", say).
struct ColorControl: View {
    /// The color shown: the setting's own, else what applies (theme, default).
    let effective: String
    /// The setting's own value, nil when it is not set.
    let value: String?
    var presets: [Setting.Option] = []
    let title: String
    let set: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            if !presets.isEmpty {
                Menu {
                    ForEach(presets) { preset in
                        Button(preset.name) { set(preset.value) }
                    }
                } label: {
                    Text(presets.first { $0.value == value }?.name ?? "Presets")
                }
                .fixedSize()
                .help("A value that follows the cell under it")
            }
            CommitField("#RRGGBB", text: value ?? effective, width: 84, monospaced: true) { set($0) }
            // Taken when the picker closes: a value set while it is open would
            // make a new picker under the pointer.
            BlossomColorPicker(initialColor: Color(configHex: effective), onDismiss: { color in
                let hex = color.configHex
                if hex.lowercased() != effective.lowercased() { set(hex) }
            })
                .frame(width: 22, height: 22)
                // The picker keeps the color it was made with; a value from
                // elsewhere (theme, undo, reset) makes a new one.
                .id(effective)
                .accessibilityLabel(title)
        }
    }
}

extension Color {
    /// The basic CSS color names Ghostty also accepts.
    private static let configNamedColors: [String: Color] = [
        "black": Color(red: 0, green: 0, blue: 0), "silver": Color(red: 0.75, green: 0.75, blue: 0.75),
        "gray": Color(red: 0.5, green: 0.5, blue: 0.5), "grey": Color(red: 0.5, green: 0.5, blue: 0.5),
        "white": Color(red: 1, green: 1, blue: 1), "maroon": Color(red: 0.5, green: 0, blue: 0),
        "red": Color(red: 1, green: 0, blue: 0), "purple": Color(red: 0.5, green: 0, blue: 0.5),
        "fuchsia": Color(red: 1, green: 0, blue: 1), "green": Color(red: 0, green: 0.5, blue: 0),
        "lime": Color(red: 0, green: 1, blue: 0), "olive": Color(red: 0.5, green: 0.5, blue: 0),
        "yellow": Color(red: 1, green: 1, blue: 0), "navy": Color(red: 0, green: 0, blue: 0.5),
        "blue": Color(red: 0, green: 0, blue: 1), "teal": Color(red: 0, green: 0.5, blue: 0.5),
        "aqua": Color(red: 0, green: 1, blue: 1), "cyan": Color(red: 0, green: 1, blue: 1),
        "magenta": Color(red: 1, green: 0, blue: 1), "orange": Color(red: 1, green: 0.65, blue: 0),
        "pink": Color(red: 1, green: 0.75, blue: 0.8), "brown": Color(red: 0.65, green: 0.16, blue: 0.16),
    ]

    init(configHex: String) {
        let raw = configHex.replacingOccurrences(of: "#", with: "")
        if raw.count == 6, let n = UInt64(raw, radix: 16) {
            self.init(red: Double((n >> 16) & 255) / 255, green: Double((n >> 8) & 255) / 255, blue: Double(n & 255) / 255)
        } else if let named = Self.configNamedColors[raw.lowercased()] {
            self = named
        } else {
            self = .black
        }
    }

    var configHex: String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        #if os(macOS)
            guard let color = NSColor(self).usingColorSpace(.sRGB) else { return "#000000" }
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #else
            guard UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return "#000000" }
        #endif
        func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(red), byte(green), byte(blue))
    }
}

/// A text field that sets its value when editing ends (Return, or focus
/// leaving it), not on every keystroke: a half-typed color or number is not
/// handed to Ghostty.
struct CommitField: View {
    let prompt: String
    let text: String
    var width: CGFloat? = nil
    var monospaced = false
    let commit: (String) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    init(_ prompt: String, text: String, width: CGFloat? = nil, monospaced: Bool = false, commit: @escaping (String) -> Void) {
        self.prompt = prompt
        self.text = text
        self.width = width
        self.monospaced = monospaced
        self.commit = commit
    }

    var body: some View {
        TextField(prompt, text: $draft)
            .labelsHidden()
            .focused($focused)
            .font(monospaced ? .body.monospaced() : .body)
            .multilineTextAlignment(.trailing)
            .frame(width: width)
            .onAppear { draft = text }
            .onChange(of: text) { _, new in if !focused { draft = new } }
            .onChange(of: focused) { _, now in if !now, draft != text { commit(draft) } }
            .onSubmit { if draft != text { commit(draft) } }
            #if os(iOS)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            #endif
    }
}
