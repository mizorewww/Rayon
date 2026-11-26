import Foundation

/// The syntax an opened file is highlighted as, chosen from its name (and, for
/// files without an extension, its shebang line).
public enum EditorLanguage: String, CaseIterable, Identifiable, Sendable {
    case plain
    case bash, c, cpp, css, go, html, java, javaScript, json, lua, markdown
    case perl, php, python, ruby, rust, sql, swift, toml, typeScript, yaml

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .plain: return "Plain Text"
        case .bash: return "Shell"
        case .c: return "C"
        case .cpp: return "C++"
        case .css: return "CSS"
        case .go: return "Go"
        case .html: return "HTML"
        case .java: return "Java"
        case .javaScript: return "JavaScript"
        case .json: return "JSON"
        case .lua: return "Lua"
        case .markdown: return "Markdown"
        case .perl: return "Perl"
        case .php: return "PHP"
        case .python: return "Python"
        case .ruby: return "Ruby"
        case .rust: return "Rust"
        case .sql: return "SQL"
        case .swift: return "Swift"
        case .toml: return "TOML"
        case .typeScript: return "TypeScript"
        case .yaml: return "YAML"
        }
    }

    private static let byExtension: [String: EditorLanguage] = [
        "sh": .bash, "bash": .bash, "zsh": .bash, "ksh": .bash, "env": .bash,
        "c": .c, "h": .c,
        "cc": .cpp, "cpp": .cpp, "cxx": .cpp, "hpp": .cpp, "hh": .cpp,
        "css": .css, "scss": .css,
        "go": .go,
        "html": .html, "htm": .html, "xml": .html, "svg": .html, "plist": .html,
        "java": .java, "kt": .java,
        "js": .javaScript, "mjs": .javaScript, "cjs": .javaScript, "jsx": .javaScript,
        "json": .json, "jsonc": .json, "json5": .json,
        "lua": .lua,
        "md": .markdown, "markdown": .markdown,
        "pl": .perl, "pm": .perl,
        "php": .php,
        "py": .python, "pyw": .python,
        "rb": .ruby,
        "rs": .rust,
        "sql": .sql,
        "swift": .swift,
        "toml": .toml,
        "ts": .typeScript, "tsx": .typeScript,
        "yml": .yaml, "yaml": .yaml,
    ]

    /// Well-known files whose name, not extension, says what they are.
    private static let byName: [String: EditorLanguage] = [
        ".bashrc": .bash, ".bash_profile": .bash, ".bash_logout": .bash, ".profile": .bash,
        ".zshrc": .bash, ".zprofile": .bash, ".zshenv": .bash, ".env": .bash,
        "Gemfile": .ruby, "Rakefile": .ruby, "Cargo.lock": .toml, "Pipfile": .toml,
        "docker-compose.yml": .yaml, "docker-compose.yaml": .yaml,
    ]

    /// Picks a language from the file name, then the shebang; plain text otherwise.
    public static func detect(fileName: String, firstLine: String? = nil) -> EditorLanguage {
        if let named = byName[fileName] { return named }
        let ext = (fileName as NSString).pathExtension.lowercased()
        if !ext.isEmpty, let language = byExtension[ext] { return language }
        if let firstLine, firstLine.hasPrefix("#!") {
            let line = firstLine.lowercased()
            if line.contains("python") { return .python }
            if line.contains("node") { return .javaScript }
            if line.contains("ruby") { return .ruby }
            if line.contains("perl") { return .perl }
            if line.contains("php") { return .php }
            if line.contains("lua") { return .lua }
            if line.contains("sh") { return .bash }
        }
        return .plain
    }
}

/// How a file is indented, read from its lines, so new lines match it.
public enum EditorIndentation: Equatable, Sendable {
    case tabs
    case spaces(Int)

    public static func detect(in text: String) -> EditorIndentation {
        var tabs = 0
        var spaceWidths: [Int: Int] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true).prefix(2000) {
            if line.hasPrefix("\t") {
                tabs += 1
            } else if line.hasPrefix(" ") {
                let width = line.prefix { $0 == " " }.count
                if width < line.count { spaceWidths[width, default: 0] += 1 }
            }
        }
        let spaced = spaceWidths.values.reduce(0, +)
        if tabs > spaced { return .tabs }
        guard spaced > 0 else { return .spaces(4) }
        // The smallest common step: 2 if most indents are even and some are 2, else 4.
        if (spaceWidths[2] ?? 0) > 0 { return .spaces(2) }
        if (spaceWidths[4] ?? 0) > 0 { return .spaces(4) }
        return .spaces(spaceWidths.max { $0.value < $1.value }?.key ?? 4)
    }
}
