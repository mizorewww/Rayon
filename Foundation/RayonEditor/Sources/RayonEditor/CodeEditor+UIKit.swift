#if os(iOS)
import RayonDesign
import RunestoneEditor
import SwiftUI
import UIKit

extension EditorLanguage {
    var treeSitter: TreeSitterLanguage? {
        switch self {
        case .plain: return nil
        case .bash: return .bash
        case .c: return .c
        case .cpp: return .cpp
        case .css: return .css
        case .go: return .go
        case .html: return .html
        case .java: return .java
        case .javaScript: return .javaScript
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
        case .typeScript: return .typeScript
        case .yaml: return .yaml
        }
    }
}

public struct CodeEditor: UIViewRepresentable {
    @Binding var text: String
    let language: EditorLanguage
    let wrapsLines: Bool
    let fontSize: CGFloat
    let onCaretChange: (EditorCaret) -> Void

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

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public func makeUIView(context: Context) -> TextView {
        let view = TextView()
        view.backgroundColor = .clear
        view.editorDelegate = context.coordinator
        view.showLineNumbers = true
        view.lineSelectionDisplayType = .line
        view.gutterLeadingPadding = 12
        view.gutterTrailingPadding = 8
        view.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 8)
        view.lineHeightMultiplier = 1.2
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        view.spellCheckingType = .no
        view.characterPairs = [Pair("(", ")"), Pair("[", "]"), Pair("{", "}"), Pair("\"", "\""), Pair("'", "'")]
        view.isFindInteractionEnabled = true
        view.verticalOverscrollFactor = 0.4
        view.isLineWrappingEnabled = wrapsLines
        switch EditorIndentation.detect(in: text) {
        case .tabs: view.indentStrategy = .tab(length: 4)
        case let .spaces(width): view.indentStrategy = .space(length: width)
        }
        context.coordinator.load(text, into: view)
        return view
    }

    public func updateUIView(_ view: TextView, context: Context) {
        context.coordinator.parent = self
        if view.isLineWrappingEnabled != wrapsLines { view.isLineWrappingEnabled = wrapsLines }
        if text != context.coordinator.lastText || fontSize != context.coordinator.lastFontSize {
            context.coordinator.load(text, into: view)
        } else if language != context.coordinator.lastLanguage {
            context.coordinator.lastLanguage = language
            if context.coordinator.inFlightLoads == 0 {
                view.setLanguageMode(language.treeSitter.map { TreeSitterLanguageMode(language: $0) } ?? PlainTextLanguageMode())
            }
        }
    }

    public final class Coordinator: NSObject, TextViewDelegate {
        var parent: CodeEditor
        var lastText = ""
        var lastLanguage = EditorLanguage.plain
        var lastFontSize: CGFloat = 13
        private var loads = 0
        private(set) var inFlightLoads = 0

        init(_ parent: CodeEditor) {
            self.parent = parent
            lastFontSize = parent.fontSize
        }

        func load(_ text: String, into view: TextView) {
            lastText = text
            lastLanguage = parent.language
            lastFontSize = parent.fontSize
            let theme = EditorTheme(size: parent.fontSize)
            let loaded = parent.language
            let language = loaded.treeSitter
            nonisolated(unsafe) let weakView = WeakBox(view)
            view.isEditable = false
            loads += 1
            inFlightLoads += 1
            let load = loads
            DispatchQueue.global(qos: .userInitiated).async {
                let state: TextViewState = language.map { TextViewState(text: text, theme: theme, language: $0) }
                    ?? TextViewState(text: text, theme: theme)
                nonisolated(unsafe) let ready = state
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.inFlightLoads = max(0, self.inFlightLoads - 1)
                    guard self.loads == load, let view = weakView.value else { return }
                    view.setState(ready)
                    view.isEditable = true
                    if self.lastLanguage != loaded {
                        view.setLanguageMode(self.lastLanguage.treeSitter.map { TreeSitterLanguageMode(language: $0) } ?? PlainTextLanguageMode())
                    }
                }
            }
        }

        public func textViewDidChange(_ textView: TextView) {
            lastText = textView.text
            parent.text = textView.text
        }

        public func textViewDidChangeSelection(_ textView: TextView) {
            if let location = textView.textLocation(at: textView.selectedRange.location) {
                parent.onCaretChange(EditorCaret(line: location.lineNumber + 1, column: location.column + 1))
            }
        }
    }
}

private struct Pair: CharacterPair {
    let leading: String
    let trailing: String
    init(_ leading: String, _ trailing: String) {
        self.leading = leading
        self.trailing = trailing
    }
}

private final class WeakBox<Value: AnyObject> {
    weak var value: Value?
    init(_ value: Value) { self.value = value }
}

#endif
