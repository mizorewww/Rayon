import SwiftUI

/// A real terminal, connected to nothing, showing a fixed sample: the
/// settings' font, ligatures, colors and cursor as the terminal draws them.
/// It shares every terminal's configuration, so it follows each change once
/// it is applied.
struct TerminalPreview: View {
    @State private var terminal: RayonTerminalView = {
        let terminal = RayonTerminalView()
        terminal.write(TerminalPreview.sample)
        return terminal
    }()

    var body: some View {
        terminal
            // Nothing typed here goes anywhere; keep the keyboard out of it.
            .allowsHitTesting(false)
            .accessibilityLabel("Terminal preview")
            .clipShape(RoundedRectangle(cornerRadius: 8))
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
