#if os(macOS)
import AppKit
import CodeEditLanguages
import CodeEditSourceEditor
import RayonDesign
import SwiftUI

extension EditorLanguage {
    /// The CodeEditLanguages grammar this language is highlighted with.
    var codeLanguage: CodeLanguage {
        switch self {
        case .plain: return .default
        case .bash: return .bash
        case .c: return .c
        case .cpp: return .cpp
        case .css: return .css
        case .go: return .go
        case .html: return .html
        case .java: return .java
        case .javaScript: return .javascript
        case .json: return .json
        case .lua: return .lua
        case .markdown: return .markdown
        case .perl: return .perl
        case .php: return .php
        case .python: return .python
        case .ruby: return .ruby
        case .rust: return .rust
        case .sql: return .sql
        case .swift: return .swift
        case .toml: return .toml
        case .typeScript: return .typescript
        case .yaml: return .yaml
        }
    }
}

/// The Mac code editor: CodeEditSourceEditor's incremental Tree-sitter
/// highlighting, line-number gutter and find panel (⌘F), in Rayon's colours.
public struct CodeEditor: View {
    @Binding var text: String
    let language: EditorLanguage
    let wrapsLines: Bool
    let fontSize: CGFloat
    let onCaretChange: (EditorCaret) -> Void
    @State private var state = SourceEditorState()
    @State private var textSync = EditorTextSync()

    public init(
        text: Binding<String>,
        language: EditorLanguage,
        wrapsLines: Bool = false,
        fontSize: CGFloat = 13,
        onCaretChange: @escaping (EditorCaret) -> Void = { _ in }
    ) {
        _text = text
        self.language = language
        self.wrapsLines = wrapsLines
        self.fontSize = fontSize
        self.onCaretChange = onCaretChange
    }

    public var body: some View {
        SourceEditor(
            $text,
            language: language.codeLanguage,
            configuration: Self.configuration(for: text, wrapsLines: wrapsLines, fontSize: fontSize),
            state: $state,
            coordinators: [textSync]
        )
            .onChange(of: text) { textSync.show($0) }
            .onChange(of: state.cursorPositions) { positions in
                guard let start = positions?.first?.start, start.line > 0 else { return }
                onCaretChange(EditorCaret(line: start.line, column: start.column))
            }
    }

    static func configuration(for text: String, wrapsLines: Bool, fontSize: CGFloat) -> SourceEditorConfiguration {
        let indentOption: IndentOption
        switch EditorIndentation.detect(in: text) {
        case .tabs: indentOption = .tab
        case let .spaces(width): indentOption = .spaces(count: width)
        }
        return SourceEditorConfiguration(
            appearance: .init(
                theme: .rayon,
                useThemeBackground: false,
                font: .monospacedSystemFont(ofSize: fontSize, weight: .regular),
                wrapLines: wrapsLines
            ),
            behavior: .init(indentOption: indentOption),
            peripherals: .init(showMinimap: false, showFoldingRibbon: false)
        )
    }
}

/// Puts text the binding gets from outside the editor into it: a snippet
/// read after the editor appeared, a file loaded again. SourceEditor takes
/// its binding's text once, when it is made, and from then on only writes
/// the binding.
@MainActor
final class EditorTextSync: @preconcurrency TextViewCoordinator {
    private weak var controller: TextViewController?

    func prepareCoordinator(controller: TextViewController) {
        self.controller = controller
    }

    func destroy() {
        controller = nil
    }

    func show(_ text: String) {
        guard let controller, controller.text != text else { return }
        controller.setText(text)
    }
}

extension EditorTheme {
    /// Editor colours drawn from the app's tokens, so the editor reads as part
    /// of Rayon in light and dark mode rather than as a separate tool. Built
    /// once: the editor reloads whenever its configuration compares unequal,
    /// and fresh dynamic colours never compare equal.
    @MainActor static let rayon = EditorTheme(
        text: Attribute(color: NSColor(Color.rxInk)),
        insertionPoint: NSColor(Color.rxAccent),
        invisibles: Attribute(color: NSColor(Color.rxInkTertiary)),
        // Not drawn (`useThemeBackground: false`), but read for its
        // brightness, which AppKit raises on for `.clear`'s gray space.
        background: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0),
        lineHighlight: NSColor(Color.rxAccent).withAlphaComponent(0.07),
        selection: .selectedTextBackgroundColor,
        keywords: Attribute(color: NSColor(EditorPalette.keyword)),
        commands: Attribute(color: NSColor(EditorPalette.function)),
        types: Attribute(color: NSColor(EditorPalette.type)),
        attributes: Attribute(color: NSColor(EditorPalette.property)),
        variables: Attribute(color: NSColor(EditorPalette.function)),
        values: Attribute(color: NSColor(EditorPalette.constant)),
        numbers: Attribute(color: NSColor(EditorPalette.number)),
        strings: Attribute(color: NSColor(EditorPalette.string)),
        characters: Attribute(color: NSColor(EditorPalette.string)),
        comments: Attribute(color: NSColor(EditorPalette.comment), italic: true)
    )
}

private extension NSColor {
    convenience init(_ swatch: EditorPalette.Swatch) {
        self.init(name: nil) { appearance in
            let rgb = swatch.components(dark: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
            return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        }
    }
}
#endif
