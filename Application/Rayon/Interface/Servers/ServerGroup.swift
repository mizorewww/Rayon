//
//  ServerGroup.swift
//  Rayon
//

import RayonModule
import SwiftUI

/// A folder of servers as the Servers page lists it; "" names Default.
struct ServerGroup: Identifiable {
    let name: String
    let machines: [RDMachine]
    var id: String { name }
}

extension RayonStore {
    /// The servers matching `search` in their folders, in folder order with
    /// Default last; empty folders only while not searching.
    func serverGroups(
        matching search: String,
        sortedBy order: [KeyPathComparator<RDMachine>] = [KeyPathComparator(\.name, comparator: .localizedStandard)]
    ) -> [ServerGroup] {
        let matching = search.isEmpty ? machines : machines.filter { $0.isQualifiedForSearch(text: search) }
        // One group per name: folders of the same name from two devices
        // would list their servers twice.
        var names: [String] = []
        for folder in folders where !names.contains(folder.name) { names.append(folder.name) }
        // A server whose folder is gone is with the default ones.
        if matching.contains(where: { folder($0.folderId) == nil }) { names.append("") }
        return names.compactMap { name in
            let inside = matching.filter { folderName(of: $0) == name }.sorted(using: order)
            if inside.isEmpty, !search.isEmpty { return nil }
            return ServerGroup(name: name, machines: inside)
        }
    }
}
