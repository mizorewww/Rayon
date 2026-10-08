import Foundation
import SwiftUI
import AppKit

/// An entirely in-memory playground. No Process, FileManager or SSH backend is used.
@MainActor
final class ConfigSandbox: ObservableObject {
    struct Line: Identifiable {
        let id = UUID()
        let text: String
        var palette: Int? = nil
    }
    @Published var lines: [Line] = [.init(text: "Ghostty Config · terminal playground", palette: 6), .init(text: "Type help. Files and commands in this preview are simulated.")]
    @Published var input = ""
    @Published var cwd = "/"
    var history: [String] = []
    var historyIndex = 0
    var files: [String: String] = [
        "/README.md": "# My Ghostty Setup\nA customized Ghostty configuration.\nGenerated with ghostty-config.",
        "/Documents/note.md": "Welcome to your Ghostty terminal!",
        "/Documents/notes.txt": "Meeting notes - Jan 1\nTODO: update ghostty config",
        "/Documents/todo.md": "# TODO\n- [ ] Configure ghostty\n- [x] Install ghostty\n- [ ] Customize colors",
        "/Downloads/setup.sh": "#!/bin/bash\napt-get install -y ghostty",
        "/Projects/ghostty-config/README.md": "# ghostty-config\nA GUI config generator for Ghostty.",
        "/Projects/ghostty-config/package.json": "{\"name\":\"ghostty-config\",\"version\":\"1.0.0\"}",
        "/Projects/ghostty-config/src/index.ts": "import App from './App.svelte';",
        "/Programs/hello.sh": "#!/bin/bash\necho 'Hello, world!'",
        "/.bash_profile": "export TERM=ghostty",
        "/.gitconfig": "[user]\nname = John\nemail = john@example.com"
    ]
    var directories: Set<String> = ["/", "/Desktop", "/Documents", "/Downloads", "/Pictures", "/Projects", "/Projects/ghostty-config", "/Projects/ghostty-config/src", "/Programs"]
    static let commands = ["cat", "cd", "clear", "date", "echo", "git", "grep", "help", "hostname", "ls", "mkdir", "pwd", "rm", "touch", "uname", "whoami"]
    var prompt: String { "rayon@ghostty \(cwd == "/" ? "~" : "~" + cwd) ❯ " }
    func submit() {
        let command = input
        input = ""
        guard !command.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        lines.append(.init(text: prompt + command, palette: 2))
        history.append(command); historyIndex = history.count
        do { for arguments in try Self.tokenize(command) { if !execute(arguments) { break } } }
        catch { output(error.localizedDescription, 1) }
        if lines.count > 2000 { lines.removeFirst(lines.count - 2000) }
    }
    func output(_ text: String, _ color: Int? = nil) { lines.append(.init(text: text, palette: color)) }
    func path(_ input: String) -> String {
        let expanded = input == "~" ? "/" : input.hasPrefix("~/") ? String(input.dropFirst()) : input
        let full = expanded.hasPrefix("/") ? expanded : cwd + "/" + expanded
        var parts: [String] = []
        for part in full.split(separator: "/") {
            if part == ".." { if !parts.isEmpty { parts.removeLast() } }
            else if part != "." { parts.append(String(part)) }
        }
        return "/" + parts.joined(separator: "/")
    }
    func historyMove(_ delta: Int) {
        historyIndex = min(history.count, max(0, historyIndex + delta))
        input = historyIndex < history.count ? history[historyIndex] : ""
    }
    func complete() {
        let parts = input.components(separatedBy: " ")
        let token = parts.last ?? ""
        let candidates: [String]
        if parts.count == 1 { candidates = Self.commands.filter { $0.hasPrefix(token) } }
        else {
            let resolved = path(token)
            let all = Array(directories) + Array(files.keys)
            candidates = all.filter { $0.hasPrefix(resolved) && $0 != "/" }.map { entry in
                let suffix = String(entry.dropFirst(resolved.count))
                return token + suffix + (directories.contains(entry) ? "/" : "")
            }.sorted()
        }
        if candidates.count == 1 { input = (parts.dropLast() + [candidates[0]]).joined(separator: " ") }
        else if !candidates.isEmpty { output(candidates.joined(separator: "   "), 4) }
    }
    @discardableResult func execute(_ args: [String]) -> Bool {
        guard let command = args.first else { return true }
        let values = Array(args.dropFirst())
        let operands = values.filter { !$0.hasPrefix("-") }
        func fail(_ message: String) -> Bool { output("\(command): \(message)", 1); return false }
        switch command {
        case "help":
            output("Available commands:\n" + Self.commands.joined(separator: "  ") + "\n\nTab completes commands and paths. ↑/↓ recall history.\nQuoted arguments and && command chains are supported.\nCtrl+C cancels input; Ctrl+L clears the preview.", 6)
        case "clear": lines.removeAll(); return false
        case "echo": output(values.joined(separator: " "))
        case "pwd": output("/home/rayon" + (cwd == "/" ? "" : cwd))
        case "whoami": output("rayon")
        case "hostname": output("ghostty")
        case "date": output(Date().formatted(date: .complete, time: .standard))
        case "uname": output(values.contains("-a") ? "Darwin ghostty 24.0.0 arm64 (simulated)" : "Darwin")
        case "cd":
            let next = path(operands.first ?? "~")
            guard directories.contains(next) else { return fail("no such directory: \(operands.first ?? "")") }
            cwd = next
        case "ls":
            let target = path(operands.first ?? ".")
            if files[target] != nil { output(target.components(separatedBy: "/").last ?? target); return true }
            guard directories.contains(target) else { return fail("no such directory") }
            let prefix = target == "/" ? "/" : target + "/"
            let entries = (Array(files.keys) + Array(directories)).filter { $0.hasPrefix(prefix) && $0 != target && !$0.dropFirst(prefix.count).contains("/") }.sorted()
            for entry in entries {
                let name = String(entry.dropFirst(prefix.count))
                if name.hasPrefix(".") && !values.contains(where: { $0.contains("a") && $0.hasPrefix("-") }) { continue }
                let isDir = directories.contains(entry)
                output((values.contains(where: { $0.hasPrefix("-") && $0.contains("l") }) ? (isDir ? "drwxr-xr-x  rayon  " : "-rw-r--r--  rayon  ") : "") + name + (isDir ? "/" : ""), isDir ? 4 : nil)
            }
        case "cat":
            guard !operands.isEmpty else { return fail("missing file operand") }
            for file in operands { guard let text = files[path(file)] else { return fail("no such file: \(file)") }; output(text) }
        case "grep":
            guard operands.count >= 2 else { return fail("usage: grep pattern file...") }
            let pattern = operands[0]; var found = false
            for file in operands.dropFirst() {
                guard let text = files[path(file)] else { return fail("no such file: \(file)") }
                for (index, line) in text.components(separatedBy: "\n").enumerated() {
                    let matches = values.contains("-i") ? line.localizedCaseInsensitiveContains(pattern) : line.contains(pattern)
                    if matches != values.contains("-v") { found = true; output((values.contains("-n") ? "\(index + 1):" : "") + line, 3) }
                }
            }
            return found
        case "mkdir", "touch":
            guard !operands.isEmpty else { return fail("missing operand") }
            for operand in operands {
                let next = path(operand)
                let parent = String(next.prefix(upTo: next.lastIndex(of: "/")!)); let parentPath = parent.isEmpty ? "/" : parent
                if command == "mkdir" && values.contains("-p") {
                    var partial = ""; for component in next.split(separator: "/") { partial += "/" + component; directories.insert(partial) }
                } else {
                    guard directories.contains(parentPath) else { return fail("parent directory does not exist") }
                    if command == "mkdir" { guard files[next] == nil && !directories.contains(next) else { return fail("file exists") }; directories.insert(next) }
                    else { if files[next] == nil { files[next] = "" } }
                }
            }
        case "rm":
            guard !operands.isEmpty else { return fail("missing operand") }
            for operand in operands {
                let target = path(operand)
                if directories.contains(target) {
                    guard target != "/", values.contains(where: { $0.hasPrefix("-") && $0.contains("r") }) else { return fail("directory requires -r") }
                    directories = directories.filter { $0 != target && !$0.hasPrefix(target + "/") }
                    files = files.filter { !$0.key.hasPrefix(target + "/") }
                } else if files.removeValue(forKey: target) == nil && !values.contains("-f") { return fail("no such file") }
            }
        case "git":
            switch operands.first {
            case "status": output("On branch main\nChanges to be committed:\n  modified: README.md", 2); output("Changes not staged:\n  modified: package.json", 1)
            case "log": output("a3f9c12 feat: add background image settings\nb81e204 fix: correct palette reset logic\nc0d3a99 refactor: split registry into modules", 3)
            case "diff": output("--- a/package.json\n+++ b/package.json", 6); output("- version: 1.0.0", 1); output("+ version: 1.1.0", 2)
            case "branch": output("* main\n  develop\n  feature/background-image", 2)
            case "add": output("Files staged (simulated)", 2)
            case "commit": output("[main 42ab001] \(values.last ?? "Update")\n 1 file changed (simulated)", 2)
            default: return fail("supported subcommands: status, log, diff, branch, add, commit")
            }
        default: return fail("command not found. Type help.")
        }
        return true
    }
    static func tokenize(_ source: String) throws -> [[String]] {
        var commands: [[String]] = []; var args: [String] = []; var token = ""; var quote: Character?; var escaped = false; var active = false
        let chars = Array(source); var index = 0
        func flush() { if active { args.append(token); token = ""; active = false } }
        while index < chars.count {
            let c = chars[index]
            if escaped { token.append(c); active = true; escaped = false }
            else if c == "\\" && quote != "'" { escaped = true; active = true }
            else if let q = quote { if c == q { quote = nil } else { token.append(c) } }
            else if c == "\"" || c == "'" { quote = c; active = true }
            else if c == "&" && index + 1 < chars.count && chars[index + 1] == "&" { flush(); commands.append(args); args = []; index += 1 }
            else if c.isWhitespace { flush() }
            else { token.append(c); active = true }
            index += 1
        }
        guard quote == nil, !escaped else { throw ConfigError.message("Unterminated quote or escape") }
        flush(); if !args.isEmpty { commands.append(args) }; return commands
    }
}

struct ConfigCommandInput: NSViewRepresentable {
    @ObservedObject var shell: ConfigSandbox
    let color: NSColor
    let font: NSFont
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: "")
        field.delegate = context.coordinator; field.isBordered = false; field.drawsBackground = false; field.focusRingType = .none
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.owner = self
        if field.stringValue != shell.input { field.stringValue = shell.input }
        field.textColor = color; field.font = font
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var owner: ConfigCommandInput
        init(_ owner: ConfigCommandInput) { self.owner = owner }
        func controlTextDidChange(_ obj: Notification) { if let field = obj.object as? NSTextField { owner.shell.input = field.stringValue } }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
            switch NSStringFromSelector(command) {
            case "insertNewline:": owner.shell.submit()
            case "moveUp:": owner.shell.historyMove(-1)
            case "moveDown:": owner.shell.historyMove(1)
            case "insertTab:": owner.shell.complete()
            case "cancelOperation:": owner.shell.output(owner.shell.prompt + owner.shell.input + "^C"); owner.shell.input = ""
            case "centerSelectionInVisibleArea:": owner.shell.lines.removeAll()
            default: return false
            }
            textView.string = owner.shell.input
            textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
            return true
        }
    }
}
