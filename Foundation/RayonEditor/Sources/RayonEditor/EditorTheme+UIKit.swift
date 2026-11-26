#if os(iOS)
import RayonDesign
import RunestoneEditor
import SwiftUI
import UIKit

/// Editor colours drawn from the app's tokens, so the editor reads as part of
/// Rayon in light and dark mode rather than as a separate tool.
final class EditorTheme: Runestone.Theme {
    let font: UIFont
    let lineNumberFont: UIFont

    init(size: CGFloat) {
        font = .monospacedSystemFont(ofSize: size, weight: .regular)
        lineNumberFont = .monospacedDigitSystemFont(ofSize: size * 0.85, weight: .regular)
    }

    let textColor = UIColor(Color.rxInk)
    let gutterBackgroundColor = UIColor.clear
    let gutterHairlineColor = UIColor(Color.rxHairline)
    let lineNumberColor = UIColor(Color.rxInkTertiary)
    let selectedLineBackgroundColor = UIColor(Color.rxAccent).withAlphaComponent(0.07)
    let selectedLinesLineNumberColor = UIColor(Color.rxInk)
    let selectedLinesGutterBackgroundColor = UIColor.clear
    let invisibleCharactersColor = UIColor(Color.rxInkTertiary).withAlphaComponent(0.6)
    let pageGuideHairlineColor = UIColor(Color.rxHairline)
    let pageGuideBackgroundColor = UIColor.clear
    let markedTextBackgroundColor = UIColor(Color.rxAccent).withAlphaComponent(0.15)

    // Syntax colours, shared with the Mac editor.
    private let keyword = UIColor(EditorPalette.keyword)
    private let string = UIColor(EditorPalette.string)
    private let number = UIColor(EditorPalette.number)
    private let comment = UIColor(EditorPalette.comment)
    private let type = UIColor(EditorPalette.type)
    private let function = UIColor(EditorPalette.function)
    private let property = UIColor(EditorPalette.property)
    private let constant = UIColor(EditorPalette.constant)

    func textColor(for highlightName: String) -> UIColor? {
        if highlightName.hasPrefix("variable.builtin") { return constant }
        switch highlightName.split(separator: ".").first.map(String.init) ?? highlightName {
        case "keyword", "include", "conditional", "repeat", "exception", "storageclass": return keyword
        case "string", "character", "escape": return string
        case "number", "float", "boolean": return number
        case "comment": return comment
        case "type", "constructor", "namespace", "tag": return type
        case "function", "method": return function
        case "property", "field", "attribute", "label": return property
        case "constant": return constant
        case "operator", "punctuation": return UIColor(Color.rxInkSecondary)
        default: return nil
        }
    }

    func fontTraits(for highlightName: String) -> FontTraits {
        highlightName.hasPrefix("comment") ? [.italic] : []
    }
}

private extension UIColor {
    convenience init(_ swatch: EditorPalette.Swatch) {
        self.init { traits in
            let rgb = swatch.components(dark: traits.userInterfaceStyle == .dark)
            return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        }
    }
}
#endif
