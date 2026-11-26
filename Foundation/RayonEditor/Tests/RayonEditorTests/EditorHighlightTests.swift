#if os(macOS)
import CodeEditLanguages
import CodeEditSourceEditor
@testable import RayonEditor
import SwiftTreeSitter
import XCTest

/// The Mac editor's grammars and highlight queries: what each sample is
/// coloured as, read the way CodeEditSourceEditor reads it (capture name to
/// theme bucket).
final class EditorHighlightTests: XCTestCase {
    private func captures(_ text: String, as language: EditorLanguage) throws -> [(text: String, capture: CaptureName)] {
        let codeLanguage = language.codeLanguage
        let grammar = try XCTUnwrap(codeLanguage.language, language.title)
        let query = try XCTUnwrap(TreeSitterModel.shared.query(for: codeLanguage.id), language.title)
        let parser = Parser()
        try parser.setLanguage(grammar)
        let tree = try XCTUnwrap(parser.parse(text))
        let source = text as NSString
        return query.execute(in: tree)
            .resolve(with: .init(string: text))
            .highlights()
            .compactMap { range in
                CaptureName.fromString(range.name).map { (source.substring(with: range.range), $0) }
            }
    }

    func testEveryLanguageButPlainHasAGrammar() {
        // CodeEditLanguages ships a Perl parser but no highlights query yet,
        // so Perl reads as plain text on the Mac.
        for language in EditorLanguage.allCases where language != .plain && language != .perl {
            XCTAssertNotNil(language.codeLanguage.language, language.title)
            XCTAssertNotNil(TreeSitterModel.shared.query(for: language.codeLanguage.id), language.title)
        }
    }

    func testMarkdownProseIsNotColouredAsCode() throws {
        let text = "# Notes\n\nIf you are in the for loop, do not return from it.\n"
        let keywords = try captures(text, as: .markdown).filter { $0.capture == .keyword }.map(\.text)
        XCTAssertEqual(keywords, [])
    }

    func testCSSURLIsNotAComment() throws {
        let text = "body {\n  background: url(https://example.com/a.png);\n  /* real comment */\n}\n"
        let comments = try captures(text, as: .css).filter { $0.capture == .comment }.map(\.text)
        XCTAssertEqual(comments, ["/* real comment */"])
    }

    func testSwiftKeywordsStringsAndComments() throws {
        let found = try captures("let greeting = \"hi\" // say hello\n", as: .swift)
        XCTAssertTrue(found.contains { $0.text == "let" && $0.capture == .keyword }, "\(found)")
        XCTAssertTrue(found.contains { $0.text == "hi" && $0.capture == .string }, "\(found)")
        XCTAssertTrue(found.contains { $0.text == "// say hello" && $0.capture == .comment }, "\(found)")
    }
}
#endif
