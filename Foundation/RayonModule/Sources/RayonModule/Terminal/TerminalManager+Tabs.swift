//
//  TerminalManager+Tabs.swift
//  RayonModule
//
//  Terminal tabs and split panes, shared by the macOS and iOS terminal pages:
//  which tabs sit together, which panes a split shows, where a dragged tab
//  lands, and which UU Remote sessions are left to resume.
//

import CoreGraphics
import Foundation

/// Where a tab dragged onto the terminal lands: beside or above/below the
/// tab in front, or on its own (`center`, which takes it out of its split).
public enum TerminalSnapZone: Equatable, Sendable {
    case left
    case right
    case top
    case bottom
    case center

    /// The zone under `point` in a terminal canvas of `size`: the outer
    /// 28% of each edge snaps to that side, the middle ungroups.
    public static func zone(at point: CGPoint, in size: CGSize) -> TerminalSnapZone {
        let nx = point.x / max(size.width, 1)
        let ny = point.y / max(size.height, 1)
        if nx < 0.28 { return .left }
        if nx > 0.72 { return .right }
        if ny < 0.28 { return .top }
        if ny > 0.72 { return .bottom }
        return .center
    }

    /// The part of a canvas of `size` the dropped tab would take, inset by
    /// `inset`, for the preview drawn while dragging.
    public func previewRect(in size: CGSize, inset: CGFloat = 8) -> CGRect {
        switch self {
        case .left:
            return CGRect(x: inset, y: inset, width: max(80, size.width / 2 - inset * 1.5), height: max(80, size.height - inset * 2))
        case .right:
            return CGRect(x: size.width / 2 + inset * 0.5, y: inset, width: max(80, size.width / 2 - inset * 1.5), height: max(80, size.height - inset * 2))
        case .top:
            return CGRect(x: inset, y: inset, width: max(80, size.width - inset * 2), height: max(80, size.height / 2 - inset * 1.5))
        case .bottom:
            return CGRect(x: inset, y: size.height / 2 + inset * 0.5, width: max(80, size.width - inset * 2), height: max(80, size.height / 2 - inset * 1.5))
        case .center:
            return CGRect(x: inset, y: inset, width: max(80, size.width - inset * 2), height: max(80, size.height - inset * 2))
        }
    }

    public var title: String {
        switch self {
        case .left: return String(localized: "Split Left", bundle: .module)
        case .right: return String(localized: "Split Right", bundle: .module)
        case .top: return String(localized: "Split Top", bundle: .module)
        case .bottom: return String(localized: "Split Bottom", bundle: .module)
        case .center: return String(localized: "Single View (Ungroup)", bundle: .module)
        }
    }

    public var systemImage: String {
        switch self {
        case .left, .right: return "rectangle.split.2x1"
        case .top, .bottom: return "rectangle.split.1x2"
        case .center: return "macwindow"
        }
    }
}

public extension TerminalManager {
    /// Adjacent tabs of one split group, or a tab on its own.
    struct TabCluster: Identifiable {
        public let id: String
        public let group: SplitGroup?
        public let items: [(index: Int, context: Context)]
    }

    /// The tab strip of `context`: tabs that belong to the same `SplitGroup`
    /// and sit next to each other form one cluster (one pill), so it is clear
    /// which tabs are split together.
    func tabClusters(for context: Context) -> [TabCluster] {
        let list = context.tabSiblings
        var result: [TabCluster] = []
        var i = 0
        while i < list.count {
            let ctx = list[i]
            if let group = splitGroup(containing: ctx.id) {
                var groupedItems: [(index: Int, context: Context)] = [(i, ctx)]
                var j = i + 1
                while j < list.count, splitGroup(containing: list[j].id)?.id == group.id {
                    groupedItems.append((j, list[j]))
                    j += 1
                }
                if groupedItems.count >= 2 {
                    result.append(TabCluster(id: "group-\(group.id.uuidString)", group: group, items: groupedItems))
                    i = j
                    continue
                }
            }
            result.append(TabCluster(id: "single-\(ctx.id.uuidString)", group: nil, items: [(i, ctx)]))
            i += 1
        }
        return result
    }

    /// Every terminal as tab groups: one per server, Quick Connect command
    /// or the local shell, in the order each group's first tab opened.
    var tabGroups: [[Context]] {
        var order: [String] = []
        var groups: [String: [Context]] = [:]
        for context in sessionContexts {
            let key = context.tabGroupKey
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(context)
        }
        return order.compactMap { groups[$0] }
    }

    /// The panes shown with `focused` in front: its split group's tabs in
    /// order, which may be on other servers, or the tab alone.
    func visiblePanes(for focused: Context) -> [Context] {
        let ids = splitGroups.visiblePaneIDs(focusedID: focused.id, openIDs: sessionContexts.map(\.id))
        guard ids.count >= 2 else { return [focused] }
        return ids.compactMap { id in sessionContexts.first { $0.id == id } }
    }

    /// Whether the split `focused` is in shows tabs of more than one
    /// server, Quick Connect command or the local shell.
    func splitSpansServers(_ focused: Context) -> Bool {
        Set(visiblePanes(for: focused).map(\.tabGroupKey)).count > 1
    }

    /// The open tabs that could join the split `focused` is in: every tab
    /// not already shown in it, other servers' first.
    func splitCandidates(for focused: Context) -> [Context] {
        let shown = Set(visiblePanes(for: focused).map(\.id))
        let others = sessionContexts.filter { !shown.contains($0.id) }
        return others.filter { $0.tabGroupKey != focused.tabGroupKey }
            + others.filter { $0.tabGroupKey == focused.tabGroupKey }
    }

    /// The layout a split takes when a tab picked from another server joins
    /// it beside `anchorID`: a grid once it has three panes or more, else
    /// what it has.
    func layoutForJoining(_ anchorID: Context.ID) -> SplitOrientation {
        let group = splitGroup(containing: anchorID)
        let count = (group?.memberIDs.count ?? 1) + 1
        return count >= 3 ? .grid : (group?.orientation ?? .horizontal)
    }

    /// Drops the tab `droppedID` on the terminal showing `anchor`, in
    /// `zone`. Returns the tab to show in front, nil when nothing changed.
    @discardableResult
    func applySnap(droppedID: Context.ID, onto anchor: Context, zone: TerminalSnapZone) -> Context.ID? {
        guard let dropped = anchor.tabSiblings.first(where: { $0.id == droppedID }) else { return nil }
        switch zone {
        case .center:
            ungroupSession(dropped.id)
        case .right, .left, .bottom, .top:
            guard dropped.id != anchor.id else { return nil }
            groupSessions(
                anchorID: anchor.id,
                newID: dropped.id,
                orientation: zone == .left || zone == .right ? .horizontal : .vertical,
                insertBeforeAnchor: zone == .left || zone == .top
            )
        }
        return dropped.id
    }

    /// The sessions on a UU Remote device that no open tab shows: the ones
    /// a new terminal can resume.
    func resumableUUSessions(for machine: RDMachine) async throws -> [UUTerminalSession] {
        let locallyAttachedIDs = Set(
            sessionContexts
                .filter { $0.remoteType == .machine && $0.machine.id == machine.id && !$0.closed }
                .compactMap(\.uuSessionID)
        )
        return try await UURemoteConnections.shared.sessions(for: machine).filter {
            !locallyAttachedIDs.contains($0.id)
        }
    }
}

public extension TerminalManager.Context {
    /// The tabs shown together with this one: the same server, the same
    /// Quick Connect command, or the local shell.
    @MainActor var tabSiblings: [TerminalManager.Context] {
        let all = TerminalManager.shared.sessionContexts
        switch remoteType {
        case .machine:
            return all.filter { $0.remoteType == .machine && $0.machine.id == machine.id }
        case .command:
            guard let command = command?.command else { return [self] }
            return all.filter { $0.remoteType == .command && $0.command?.command == command }
        case .local:
            return all.filter { $0.remoteType == .local }
        }
    }

    /// Shared by the tabs of one server, one Quick Connect command, or the
    /// local shell: what `tabSiblings` groups by, as a key.
    var tabGroupKey: String {
        switch remoteType {
        case .machine: return "server:\(machine.id.uuidString)"
        case .command: return command.map { "command:\($0.command)" } ?? "tab:\(id.uuidString)"
        case .local: return "local"
        }
    }

    var displayName: String {
        switch remoteType {
        case .machine: return machine.name
        case .command:
            if let command { return "\(command.username)@\(command.remoteAddress)" }
            return navigationTitle
        case .local: return String(localized: "Local Terminal", bundle: .module)
        }
    }

    /// What the status line names this terminal by: the SSH target, the
    /// command, or the UU Remote device.
    var endpointDescription: String {
        if remoteType == .local { return String(localized: "Local Shell · \(ProcessInfo.processInfo.hostName)", bundle: .module) }
        if let command { return command.command }
        if machine.isUURemoteDevice { return "UU Remote · " + machine.name }
        return machine.getCommand(insertLeadingSSH: false)
    }

    /// Connects a closed tab again, with the details it started with.
    func reconnect() {
        guard closed else { return }
        DispatchQueue.global().async {
            self.putInformation("[i] \(String(localized: "Reconnecting with the details from when this session started.", bundle: .module))")
            self.putInformation("    \(String(localized: "If the server was edited, open a new terminal instead.", bundle: .module))")
            self.processBootstrap()
        }
    }
}

public extension RayonStore {
    /// The snippets whose name, code or group contain `filter`, any case.
    func snippets(matching filter: String) -> [RDSnippet] {
        guard !filter.isEmpty else { return snippets }
        let key = filter.lowercased()
        return snippets.filter {
            $0.name.lowercased().contains(key)
                || $0.code.lowercased().contains(key)
                || $0.group.lowercased().contains(key)
        }
    }
}
