//
//  LegacyStoreImport+Notice.swift
//  RayonModule
//
//  What the user is told, once, after the first launch that brought over
//  what the previous release kept: how much came, and what did not.
//

import Foundation

extension LegacyStoreImport {
    /// The message, or nil when nothing was brought over (a fresh install,
    /// or a launch after the one that imported).
    static func notice(imported: Imported?, settings: Int) -> String? {
        var lines: [String] = []
        if let imported, imported.servers + imported.identities + imported.snippets + imported.forwards > 0 {
            let (machines, identities, snippets, forwards) = (imported.servers, imported.identities, imported.snippets, imported.forwards)
            lines.append(String(localized: "\(machines) servers, \(identities) identities, \(snippets) snippets, and \(forwards) port forwards.", bundle: .module))
        }
        if settings > 0 {
            lines.append(String(localized: "\(settings) settings.", bundle: .module))
        }
        for key in imported?.unreadableCopies ?? [] {
            let kind = kindName(key)
            lines.append(String(localized: "Not imported: a damaged copy of the \(kind) that the previous version set aside cannot be read. It is kept as it was.", bundle: .module))
        }
        guard !lines.isEmpty else { return nil }
        return ([String(localized: "Rayon brought over what its previous version kept:", bundle: .module)] + lines).joined(separator: "\n")
    }

    private static func kindName(_ key: String) -> String {
        switch key {
        case Key.machines: String(localized: "servers", bundle: .module)
        case Key.identities: String(localized: "identities", bundle: .module)
        case Key.snippets: String(localized: "snippets", bundle: .module)
        case Key.portForwards: String(localized: "port forwards", bundle: .module)
        case Key.folders: String(localized: "folders", bundle: .module)
        case Key.recent: String(localized: "recent connections", bundle: .module)
        default: String(localized: "host keys", bundle: .module)
        }
    }
}
