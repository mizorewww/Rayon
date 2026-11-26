#if os(macOS)
import CodeEditSourceEditor
@testable import RayonEditor
import XCTest

/// The Mac editor comes up with Rayon's theme: CodeEditSourceEditor reads
/// the theme background's brightness, which AppKit refuses (and traps on)
/// for a colour outside an RGB space.
@MainActor
final class EditorViewTests: XCTestCase {
    func testTheThemeBackgroundHasABrightness() {
        XCTAssertNotNil(EditorTheme.rayon.background.usingColorSpace(.sRGB))
        _ = EditorTheme.rayon.background.brightnessComponent
    }

    func testTheEditorViewLoads() {
        let text = "echo hello\n"
        for wrapsLines in [false, true] {
            let controller = TextViewController(
                string: text,
                language: EditorLanguage.bash.codeLanguage,
                configuration: CodeEditor.configuration(for: text, wrapsLines: wrapsLines, fontSize: 13),
                cursorPositions: []
            )
            controller.loadView()
            controller.viewDidLoad()
            XCTAssertNotNil(controller.textView)
        }
    }
}
#endif
