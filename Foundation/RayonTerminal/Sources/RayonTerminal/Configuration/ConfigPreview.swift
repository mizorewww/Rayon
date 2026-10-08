import SwiftUI
import AppKit

struct ConfigPreview: View {
    @ObservedObject var model: ConfigEditorModel
    @StateObject private var shell = ConfigSandbox()
    @State private var minimized = false
    @State private var dark = true
    private var document: ConfigDocument { model.document }
    private var foreground: Color { Color(configHex: document.effectiveColor("foreground", dark: dark)) }
    private var size: CGFloat { min(32, max(8, Double(document.text("font-size")) ?? 14)) }
    private var family: String { document.values("font-family").first ?? "Menlo" }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Live Preview", systemImage: "terminal").font(.headline)
                Spacer()
                Toggle("Dark", isOn: $dark).toggleStyle(.switch).controlSize(.small)
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    ForEach([Color.red, .yellow, .green], id: \.self) { color in Circle().fill(color.opacity(0.8)).frame(width: 9, height: 9) }
                    Text("rayon — playground").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { minimized.toggle() } label: { Image(systemName: minimized ? "plus" : "minus") }.buttonStyle(.borderless)
                }.padding(10).background(.bar)
                if !minimized {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(shell.lines) { line in
                                    Text(line.text).foregroundStyle(line.palette.map { Color(configHex: document.effectivePalette($0, dark: dark)) } ?? foreground)
                                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                }
                                HStack(spacing: 2) {
                                    Text(shell.prompt).foregroundStyle(Color(configHex: document.effectivePalette(2, dark: dark)))
                                    ConfigCommandInput(shell: shell, color: NSColor(foreground), font: NSFont(name: family, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)).frame(minWidth: 70)
                                }.id("input")
                            }.font(.custom(family, size: size)).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(minHeight: 200, idealHeight: 280, maxHeight: 420)
                            .background(Color(configHex: document.effectiveColor("background", dark: dark)))
                            .onChange(of: shell.lines.count) { _ in proxy.scrollTo("input", anchor: .bottomLeading) }
                    }
                }
            }.clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.12)))
            HStack(spacing: 2) { ForEach(0..<16, id: \.self) { i in Rectangle().fill(Color(configHex: document.effectivePalette(i, dark: dark))).frame(height: 14).help("Palette \(i)") } }.clipShape(RoundedRectangle(cornerRadius: 3))
            HStack {
                Text("Selected text").padding(5).foregroundStyle(Color(configHex: document.effectiveColor("selection-foreground", dark: dark)))
                    .background(Color(configHex: document.effectiveColor("selection-background", dark: dark)))
                Spacer()
                Text("Cursor")
                ConfigCursorPreview(document: document, dark: dark)
            }.font(.system(.caption, design: .monospaced))
            HStack {
                ConfigIconPreview(document: document).frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Ghostty app icon").font(.caption.bold())
                    Text("Icon and window settings are exported for standalone Ghostty.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Preview commands use a temporary, simulated filesystem. Changes appear here immediately; open SSH sessions change only after Save & Apply.").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }.padding(18)
    }
}
struct ConfigCursorPreview: View {
    let document: ConfigDocument
    let dark: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.6)) { context in
            let blink = document.text("cursor-style-blink") == "true"
            let visible = !blink || Int(context.date.timeIntervalSince1970 / 0.6) % 2 == 0
            let style = document.text("cursor-style")
            ZStack(alignment: style == "underline" ? .bottom : .leading) {
                Text("A").foregroundStyle(Color(configHex: document.effectiveColor("foreground", dark: dark)))
                Rectangle().fill(Color(configHex: document.effectiveColor("cursor-color", dark: dark)))
                    .frame(width: style == "bar" ? 2 : 11, height: style == "underline" ? 2 : 17)
                    .opacity(visible ? Double(document.text("cursor-opacity")) ?? 1 : 0)
            }.frame(width: 15, height: 20)
        }
    }
}
struct ConfigIconPreview: View {
    let document: ConfigDocument
    private func image(_ name: String) -> Image {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"), let image = NSImage(contentsOf: url) else { return Image(systemName: "desktopcomputer").resizable() }
        return Image(nsImage: image).resizable()
    }
    var body: some View {
        if document.text("macos-icon") == "custom-style" {
            ZStack {
                image(document.text("macos-icon-frame"))
                LinearGradient(colors: document.text("macos-icon-screen-color").components(separatedBy: ",").map { Color(configHex: $0.trimmingCharacters(in: .whitespaces)) }, startPoint: .bottom, endPoint: .top).mask(image("mask"))
                Color(configHex: document.text("macos-icon-ghost-color")).mask(image("ghost"))
                image("crt"); image("gloss")
            }
        } else if document.text("macos-icon") == "custom" {
            VStack { image("official").scaledToFit(); Text("Custom file").font(.caption2) }
        } else { image(document.text("macos-icon").isEmpty ? "official" : document.text("macos-icon")).scaledToFit() }
    }
}
struct ConfigFontPlayground: View {
    @State private var family = "Menlo"
    @State private var size = 16.0
    @State private var bold = false
    @State private var italic = false
    @State private var sample = "The quick brown fox jumps over the lazy dog.\n0123456789  != == === => -> >= <=\n日本語 · 中文 · Ελληνικά · Кириллица\n󰊢 󰆍 󰅩    \n\nfunc hello() {\n    print(\"Hello, Ghostty!\")\n}"
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Font Playground").font(.largeTitle.bold())
            Text("Experiment with installed fonts. These controls do not change your terminal configuration. Install JetBrains Mono or a Nerd Font through macOS to preview it here.").foregroundStyle(.secondary)
            HStack {
                Picker("Font", selection: $family) { ForEach(NSFontManager.shared.availableFontFamilies.sorted(), id: \.self) { Text($0).tag($0) } }
                TextField("Custom font family", text: $family).frame(width: 200)
            }
            HStack { Slider(value: $size, in: 4...60, step: 0.5); Text("\(size.formatted()) pt").monospacedDigit(); Toggle("Bold", isOn: $bold); Toggle("Italic", isOn: $italic) }
            TextEditor(text: $sample).font(font).padding(12).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10)).frame(minHeight: 340)
        }.padding(24)
    }
    private var font: Font {
        var font = Font.custom(family, size: size)
        if bold { font = font.bold() }; if italic { font = font.italic() }; return font
    }
}
