import RayonDesign
import SwiftUI

/// A real terminal, connected to nothing, showing a fixed sample: the
/// settings' font, ligatures, colors and cursor as the terminal draws them.
/// It shares every terminal's configuration, so it follows each change once
/// it is applied.
struct TerminalPreview: View {
    let terminal: RayonTerminalView

    var body: some View {
        terminal
            // Nothing typed here goes anywhere; keep the keyboard out of it.
            .allowsHitTesting(false)
            .accessibilityLabel(Text("Terminal preview", bundle: .module))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    static func makeTerminal() -> RayonTerminalView {
        let terminal = RayonTerminalView()
        terminal.write(sample)
        return terminal
    }

    /// Text, the 16 palette colors, bold and italic, a selection-like
    /// inverse run, ligatures and box drawing, then a prompt.
    static let sample: String = {
        let esc = "\u{1B}["
        var lines: [String] = []
        lines.append("\(esc)1;32mrayon@server\(esc)0m:\(esc)1;34m~/project\(esc)0m$ ls --color")
        lines.append("\(esc)34mSources\(esc)0m  \(esc)32mbuild.sh\(esc)0m  README.md  \(esc)36mlink\(esc)0m -> \(esc)35mtarget\(esc)0m")
        lines.append((0 ..< 8).map { "\(esc)\(30 + $0)m██\(esc)0m" }.joined() + "  " + (0 ..< 8).map { "\(esc)\(90 + $0)m██\(esc)0m" }.joined())
        lines.append("\(esc)1mBold\(esc)0m \(esc)3mItalic\(esc)0m \(esc)1;3mBold italic\(esc)0m \(esc)4mUnderline\(esc)0m \(esc)2mFaint\(esc)0m \(esc)7mInverse\(esc)0m")
        lines.append("-> => != === <= >= :: || && |> </> ++ www 0O1lI")
        lines.append("┌──┬──┐ ░▒▓ λ → ✓ 中文 日本語")
        lines.append("\(esc)1;32mrayon@server\(esc)0m:\(esc)1;34m~/project\(esc)0m$ ")
        return lines.joined(separator: "\r\n")
    }()
}

/// The preview above the pages it wraps, while `isShown`, folded away when
/// its disclosure is closed. It holds one terminal, made the first time it
/// shows and kept while the pages change, so wrap it around the page switch
/// rather than put it inside a page.
private struct TerminalPreviewSlot: ViewModifier {
    let isShown: Bool
    @AppStorage("TerminalSettingsShowsPreview") private var isExpanded = true
    @State private var terminal: RayonTerminalView?

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            if isShown {
                DisclosureGroup(isExpanded: $isExpanded.animation()) {
                    if let terminal {
                        TerminalPreview(terminal: terminal)
                            .frame(height: 168)
                            .padding(.top, 6)
                    }
                } label: {
                    Text("Preview", bundle: .module)
                        .font(.headline)
                }
                .padding([.horizontal, .top])
                .transition(.opacity)
            }
            content
        }
        #if os(iOS)
        // The preview sits on the backdrop the form below is drawn on.
        .background(RXBackdrop().ignoresSafeArea())
        #endif
        .onChange(of: isShown && isExpanded, initial: true) { _, shown in
            if shown, terminal == nil { terminal = TerminalPreview.makeTerminal() }
        }
    }
}

public extension View {
    /// The live terminal preview above these terminal settings pages while
    /// `isShown`; see `TerminalSettingsCategory.previews`.
    func terminalPreview(isShown: Bool) -> some View {
        modifier(TerminalPreviewSlot(isShown: isShown))
    }
}
