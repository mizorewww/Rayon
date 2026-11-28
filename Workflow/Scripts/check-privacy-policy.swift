// Fails when a privacy policy shows literal emphasis markers once rendered
// the way the About page renders it: CommonMark leaves `**` open when it
// sits between punctuation and a letter, which full-width colons trigger.
import Foundation

let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/Privacy")
let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "md" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
guard !files.isEmpty else {
    print("error: no privacy policies in \(directory.path)")
    exit(1)
}
var failed = false
for file in files {
    let markdown = try String(contentsOf: file, encoding: .utf8)
    let text = String(try AttributedString(markdown: markdown, options: .init(interpretedSyntax: .full)).characters)
    for marker in ["**", "__"] where text.contains(marker) {
        print("error: \(file.lastPathComponent) renders a literal \(marker)")
        failed = true
    }
}
print("Checked \(files.count) privacy policies")
exit(failed ? 1 : 0)
