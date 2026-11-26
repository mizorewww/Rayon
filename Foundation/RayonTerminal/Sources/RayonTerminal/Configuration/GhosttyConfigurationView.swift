import CoreText
import GhosttyTheme
import RayonDesign
import SwiftUI

/// The terminal's core settings over a live preview: a real terminal showing a
/// fixed sample, drawn with the settings as applied. Everything else Ghostty
/// offers is set in `config.ghostty`, which `openConfigFile` asks the app to
/// open in its editor. A plain view: the app decides where it goes in Settings.
public struct GhosttyConfigurationView: View {
    @Binding private var copyOnSelect: Bool
    @Binding private var clipboardSharing: Bool
    private let openConfigFile: (URL) -> Void
    @State private var config = RayonTerminalConfiguration.config
    @State private var issue = RayonTerminalConfiguration.loadIssue
    @StateObject private var preview = PreviewTerminal()

    /// - Parameters:
    ///   - copyOnSelect, clipboardSharing: the app's clipboard preferences,
    ///     applied to every terminal as they change.
    ///   - openConfigFile: opens `config.ghostty` in the app's editor; save it
    ///     with `RayonTerminalConfiguration.save(_:)`.
    public init(copyOnSelect: Binding<Bool>, clipboardSharing: Binding<Bool>, openConfigFile: @escaping (URL) -> Void) {
        _copyOnSelect = copyOnSelect
        _clipboardSharing = clipboardSharing
        self.openConfigFile = openConfigFile
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: RX.Space.s6) {
            preview.terminal
                .frame(height: 180)
                .rxCardChrome()
                .accessibilityLabel("Terminal preview")
            group("Appearance") {
                RXFormRow("Theme") {
                    Picker("Theme", selection: value("theme")) {
                        Text("Default").tag("")
                        ForEach(themeNames, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                RXFormRow("Background opacity") {
                    RXSlider(value: number("background-opacity", default: 1), in: 0.2 ... 1, step: 0.05)
                        .frame(maxWidth: 260)
                }
            }
            group("Text") {
                RXFormRow("Font") {
                    Picker("Font", selection: value("font-family")) {
                        Text("Default (JetBrains Mono)").tag("")
                        ForEach(fontFamilies, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                RXFormRow("Size") {
                    RXSlider(value: number("font-size", default: RayonTerminalConfiguration.defaultFontSize), in: 6 ... 36, step: 0.5, unit: "pt")
                        .frame(maxWidth: 260)
                }
            }
            group("Cursor") {
                RXFormRow("Style") {
                    RXSegmented(selection: value("cursor-style", default: "block"), options: [
                        .init("block", "Block"), .init("bar", "Bar"), .init("underline", "Underline"),
                    ], caps: false)
                }
                SwitchRow("Blink", isOn: Binding(
                    get: { (config.value("cursor-style-blink") ?? "true") != "false" },
                    set: { set("cursor-style-blink", $0 ? "true" : "false") }
                ))
            }
            group("Clipboard") {
                SwitchRow(
                    "Copy on select",
                    description: "Copy text to the clipboard as soon as you finish selecting it.",
                    isOn: $copyOnSelect
                )
                SwitchRow(
                    "Share clipboard with remote programs",
                    description: "Programs running on the server may read and write the clipboard (OSC 52), so a copy in vim or tmux lands here.",
                    isOn: $clipboardSharing
                )
            }
            group("Advanced") {
                RXFormRow("config.ghostty", description: "Every other Ghostty setting: keybindings, palette, padding, scrollback and more.") {
                    Button("Open in Editor") { openConfigFile(RayonTerminalConfiguration.fileURL) }
                        .buttonStyle(.rx)
                }
            }
            if let issue {
                HelpText(issue, isError: true)
                    .textSelection(.enabled)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: RayonTerminalConfiguration.didApply)) { _ in
            config = RayonTerminalConfiguration.config
            issue = nil
        }
        .onChange(of: copyOnSelect) { RayonTerminalConfiguration.setCopyOnSelect($0) }
        .onChange(of: clipboardSharing) { RayonTerminalConfiguration.setClipboardSharing($0) }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: RX.Space.s2) {
            CapsLabel(title)
                .padding(.leading, RX.Space.s4)
            RXDividedStack { content() }
                .padding(.horizontal, RX.Space.s4)
                .background(Color.clear.rxCard(padding: 0))
        }
    }

    // MARK: Values

    private func set(_ key: String, _ value: String?) {
        do {
            try RayonTerminalConfiguration.set(key, value.map { [$0] } ?? [])
        } catch {
            issue = error.localizedDescription
        }
    }

    /// An empty selection removes the key, so Ghostty's default applies.
    private func value(_ key: String, default fallback: String = "") -> Binding<String> {
        Binding(
            get: { config.value(key) ?? fallback },
            set: { set(key, $0.isEmpty ? nil : $0) }
        )
    }

    private func number(_ key: String, default fallback: Double) -> Binding<Double> {
        Binding(
            get: { config.value(key).flatMap(Double.init) ?? fallback },
            set: { set(key, String(format: "%g", $0)) }
        )
    }

    /// Bundled themes, plus the file's own value when it names something else
    /// (a light/dark pair), so the picker can show it.
    private var themeNames: [String] {
        let names = GhosttyThemeCatalog.allThemes.map(\.name)
        guard let current = config.value("theme"), !current.isEmpty, !names.contains(current) else { return names }
        return [current] + names
    }

    private var fontFamilies: [String] {
        let families = Self.monospacedFamilies
        guard let current = config.value("font-family"), !current.isEmpty, !families.contains(current) else { return families }
        return [current] + families
    }

    /// Monospaced font families installed on this device.
    private static let monospacedFamilies: [String] = {
        let collection = CTFontCollectionCreateFromAvailableFonts(nil)
        let descriptors = CTFontCollectionCreateMatchingFontDescriptors(collection) as? [CTFontDescriptor] ?? []
        var families = Set<String>()
        for descriptor in descriptors {
            let traits = CTFontDescriptorCopyAttribute(descriptor, kCTFontTraitsAttribute) as? [CFString: Any]
            let symbolic = (traits?[kCTFontSymbolicTrait] as? NSNumber)?.uint32Value ?? 0
            guard symbolic & CTFontSymbolicTraits.traitMonoSpace.rawValue != 0,
                  let family = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String,
                  !family.hasPrefix(".")
            else { continue }
            families.insert(family)
        }
        return families.sorted()
    }()
}

/// The preview's terminal: a real surface that is never connected to anything,
/// so what is typed into it goes nowhere.
@MainActor
private final class PreviewTerminal: ObservableObject {
    let terminal = RayonTerminalView()

    init() { terminal.write(Self.sample) }

    private static let sample: String = {
        let esc = "\u{1B}["
        let swatches = (0 ..< 8).map { "\(esc)4\($0)m   " }.joined() + "\(esc)0m\r\n"
            + (0 ..< 8).map { "\(esc)10\($0)m   " }.joined() + "\(esc)0m\r\n"
        return "\(esc)1;32muser@rayon\(esc)0m:\(esc)1;34m~/project\(esc)0m$ ls\r\n"
            + "\(esc)1;34msrc\(esc)0m  \(esc)1;32mbuild.sh\(esc)0m  \(esc)36mdocs\(esc)0m  README.md\r\n"
            + "\(esc)1mBold\(esc)0m  \(esc)3mItalic\(esc)0m  \(esc)4mUnderline\(esc)0m  \(esc)2mDim\(esc)0m  -> => != === <= >=\r\n"
            + swatches
            + "\(esc)1;32muser@rayon\(esc)0m:\(esc)1;34m~/project\(esc)0m$ "
    }()
}
