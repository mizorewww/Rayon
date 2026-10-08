import Foundation

struct ConfigKeybindingCatalog: Decodable, Sendable {
    let keys: [String]
    let actions: [ConfigAction]
    static let shared = try! JSONDecoder().decode(Self.self, from: Data(contentsOf:
        Bundle.module.url(forResource: "keybindings", withExtension: "json")!))
}
struct ConfigAction: Decodable, Identifiable, Sendable {
    var id: String { name }
    let name: String
    let description: String?
    let type: String
    let options: [String]?
    let allowEmpty: Bool?
    let min: Double?
}
struct ConfigKeybinding: Equatable {
    var prefixes: [String] = []
    var steps: [String] = ["super+k"]
    var action = "ignore"
    var argument: String? = nil
    var errors: [String] = []
    var trigger: String { prefixes.map { $0 + ":" }.joined() + steps.joined(separator: ">") }
    var rendered: String { trigger + "=" + action + (argument.map { ":" + $0 } ?? "") }
    var canonical: String { steps.map(Self.canonicalStep).joined(separator: ">") }

    init() {}
    init(_ text: String) {
        guard let eq = text.firstIndex(of: "=") else { errors = ["Missing '=' between trigger and action"]; return }
        var trigger = String(text[..<eq]).filter { !$0.isWhitespace }
        while let colon = trigger.firstIndex(of: ":"), ["all", "global", "unconsumed", "performable"].contains(String(trigger[..<colon])) {
            prefixes.append(String(trigger[..<colon])); trigger = String(trigger[trigger.index(after: colon)...])
        }
        steps = trigger.components(separatedBy: ">")
        let tail = text[text.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        if let colon = tail.firstIndex(of: ":") {
            action = String(tail[..<colon]); argument = String(tail[tail.index(after: colon)...])
        } else { action = tail }
        if steps.count > 1 && prefixes.contains(where: { $0 == "all" || $0 == "global" }) { errors.append("Global/all bindings cannot be sequences") }
        for step in steps {
            let (mods, key) = Self.splitStep(step)
            if mods.count > 4 || mods.contains(where: { !["super", "ctrl", "shift", "alt"].contains($0) }) { errors.append("Invalid modifiers in \(step)") }
            if key.isEmpty || !(key.unicodeScalars.count == 1 || key.hasPrefix("physical:") || ConfigKeybindingCatalog.shared.keys.contains(key)) { errors.append("Invalid key: \(key)") }
        }
        guard let definition = ConfigKeybindingCatalog.shared.actions.first(where: { $0.name == action }) else {
            errors.append("Unknown action: \(action)"); return
        }
        let arg = argument ?? ""
        switch definition.type {
        case "none": if !arg.isEmpty { errors.append("This action takes no argument") }
        case "free", "text": if argument == nil && definition.allowEmpty != true { errors.append("An argument is required") }
        case "enum": if !(argument == nil && definition.allowEmpty == true) && !(definition.options ?? []).contains(arg) { errors.append("Choose a valid action argument") }
        case "number", "integer", "unsignedInteger":
            guard let n = Double(arg), n.isFinite else { errors.append("A numeric argument is required"); return }
            if definition.type != "number" && n.rounded() != n { errors.append("An integer is required") }
            if definition.type == "unsignedInteger" && n < (definition.min ?? 0) { errors.append("Argument is below its minimum") }
        case "resize":
            let parts = arg.components(separatedBy: ",")
            if parts.count != 2 || !["up", "down", "left", "right"].contains(parts[0]) || Int(parts.last ?? "").map({ $0 >= 0 }) != true { errors.append("Use direction,offset (for example right,10)") }
        default: break
        }
    }
    static func splitStep(_ step: String) -> ([String], String) {
        var mods: [String] = []
        var key = step
        if step == "+" { return ([], "+") }
        if step.hasSuffix("++") { key = "+"; mods = String(step.dropLast(2)).components(separatedBy: "+") }
        else if let plus = step.lastIndex(of: "+") { mods = String(step[..<plus]).components(separatedBy: "+"); key = String(step[step.index(after: plus)...]) }
        let aliases = ["cmd": "super", "command": "super", "control": "ctrl", "opt": "alt", "option": "alt"]
        mods = mods.filter { !$0.isEmpty }.map { aliases[$0.lowercased()] ?? $0.lowercased() }
        let lowered = key.lowercased()
        if !ConfigKeybindingCatalog.shared.keys.contains(lowered), key.unicodeScalars.count > 1, !lowered.hasPrefix("physical:") {
            key = key.replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1_$2", options: .regularExpression)
                .replacingOccurrences(of: "([a-zA-Z])([0-9])", with: "$1_$2", options: .regularExpression)
        }
        return (mods, key.lowercased())
    }
    static func canonicalStep(_ text: String) -> String {
        let (mods, key) = splitStep(text)
        return (mods.sorted() + [key]).joined(separator: "+")
    }
}
