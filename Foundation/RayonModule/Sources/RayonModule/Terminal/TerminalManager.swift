//
//  TerminalManager.swift
//  RayonModule
//
//  Shared terminal session manager across macOS and iOS.
//

import RayonTerminal
import Combine
import Foundation

extension TerminalSurfaceBridge: TerminalSessionSurface {}

@MainActor
public final class TerminalManager: ObservableObject {
    public static let shared = TerminalManager()

    private init() {}

    /// How a split lays out its panes: side by side, stacked, or in rows
    /// and columns (see `SplitGrid`).
    public enum SplitOrientation: String, CaseIterable, Sendable {
        case horizontal
        case vertical
        case grid

        /// The layout the orientation switch moves to: side by side, then
        /// stacked, then a grid, then side by side again.
        public var next: SplitOrientation {
            switch self {
            case .horizontal: return .vertical
            case .vertical: return .grid
            case .grid: return .horizontal
            }
        }

        public var systemImage: String {
            switch self {
            case .horizontal: return "rectangle.split.2x1"
            case .vertical: return "rectangle.split.1x2"
            case .grid: return "square.grid.2x2"
            }
        }

        public var title: String {
            switch self {
            case .horizontal: return "Side by Side"
            case .vertical: return "Stacked"
            case .grid: return "Grid"
            }
        }
    }

    public struct SplitGroup: Identifiable, Equatable {
        public var id: UUID = .init()
        public var memberIDs: [Context.ID]
        public var orientation: SplitOrientation = .horizontal

        public init(id: UUID = .init(), memberIDs: [Context.ID], orientation: SplitOrientation = .horizontal) {
            self.id = id
            self.memberIDs = memberIDs
            self.orientation = orientation
        }
    }

    public final class Context: TerminalContext, @unchecked Sendable {
        private let surfaceBridge = TerminalSurfaceBridge()
        public var termInterface: RayonTerminalView { surfaceBridge.termInterface }

        public init(machine: RDMachine, resuming uuSession: UInt32? = nil) {
            super.init(machine: machine, surface: surfaceBridge, resuming: uuSession)
            termInterface.setTerminalFontSize(with: RayonStore.workerTerminalFontSize)
        }

        public init(command: SSHCommandReader) {
            super.init(command: command, surface: surfaceBridge)
            termInterface.setTerminalFontSize(with: RayonStore.workerTerminalFontSize)
        }

        public init(localShell: Bool) {
            super.init(localShell: surfaceBridge)
            termInterface.setTerminalFontSize(with: RayonStore.workerTerminalFontSize)
        }
    }

    @Published public var sessionContexts: [Context] = []
    @Published public var splitGroups: [SplitGroup] = []

    /// Alias used by the iOS app.
    public var terminals: [Context] {
        get { sessionContexts }
        set { sessionContexts = newValue }
    }

    public func createSession(
        withMachineObject machine: RDMachine,
        resuming uuSession: UInt32? = nil,
        completion: @escaping (Context) -> Void = { _ in }
    ) {
        let context = Context(machine: machine, resuming: uuSession)
        sessionContexts.append(context)
        RayonStore.shared.storeRecentIfNeeded(from: machine.id)
        completion(context)
    }

    @discardableResult
    public func createSession(withCommand command: SSHCommandReader) -> Context {
        let context = Context(command: command)
        sessionContexts.append(context)
        RayonStore.shared.storeRecentIfNeeded(from: command)
        return context
    }

    @discardableResult
    public func createLocalSession() -> Context {
        let context = Context(localShell: true)
        sessionContexts.append(context)
        return context
    }

    public func sessionAlive(forContext contextId: Context.ID) -> Bool {
        !(sessionContexts.first { $0.id == contextId }?.closed ?? true)
    }

    public func closeSession(withMachineID machineId: RDMachine.ID) {
        if let index = sessionContexts.firstIndex(where: { $0.machine.id == machineId }) {
            let context = sessionContexts.remove(at: index)
            removeFromSplitGroups(context.id)
            context.processShutdown()
            context.destroyedSession = true
        }
    }

    public func closeSession(withContextID contextId: Context.ID) {
        if let index = sessionContexts.firstIndex(where: { $0.id == contextId }) {
            let context = sessionContexts.remove(at: index)
            removeFromSplitGroups(context.id)
            context.processShutdown()
            context.destroyedSession = true
        }
    }

    /// Alias used by the iOS app.
    public func end(for contextId: UUID) {
        closeSession(withContextID: contextId)
    }

    public func closeAll() {
        for context in sessionContexts {
            context.processShutdown()
            context.destroyedSession = true
        }
        sessionContexts = []
        splitGroups = []
    }

    public func splitGroup(containing id: Context.ID) -> SplitGroup? {
        splitGroups.first { $0.memberIDs.contains(id) }
    }

    public func groupSessions(
        anchorID: Context.ID,
        newID: Context.ID,
        orientation: SplitOrientation,
        insertBeforeAnchor: Bool = false
    ) {
        guard anchorID != newID else { return }
        splitGroups.group(anchorID: anchorID, newID: newID, orientation: orientation, insertBeforeAnchor: insertBeforeAnchor)

        // Keep grouped tabs adjacent in `sessionContexts` in the exact order of `memberIDs`.
        if let group = splitGroup(containing: anchorID) {
            alignSessionOrder(for: group)
        }
    }

    public func setSplitOrientation(for contextID: Context.ID, orientation: SplitOrientation) {
        guard let idx = splitGroups.firstIndex(where: { $0.memberIDs.contains(contextID) }) else { return }
        splitGroups[idx].orientation = orientation
    }

    public func ungroupSession(_ id: Context.ID) {
        removeFromSplitGroups(id)
    }

    private func removeFromSplitGroups(_ id: Context.ID) {
        splitGroups.removeMember(id)
    }

    private func alignSessionOrder(for group: SplitGroup) {
        guard let firstAnchorIdx = sessionContexts.firstIndex(where: { group.memberIDs.contains($0.id) }) else { return }
        let memberSet = Set(group.memberIDs)
        let orderedMembers = group.memberIDs.compactMap { id in sessionContexts.first { $0.id == id } }
        var remaining = sessionContexts
        remaining.removeAll { memberSet.contains($0.id) }
        let insertIndex = min(firstAnchorIdx, remaining.count)
        remaining.insert(contentsOf: orderedMembers, at: insertIndex)
        sessionContexts = remaining
    }

    public func moveSession(fromID: Context.ID, toID: Context.ID) {
        guard fromID != toID,
              let fromIndex = sessionContexts.firstIndex(where: { $0.id == fromID }),
              let toIndex = sessionContexts.firstIndex(where: { $0.id == toID })
        else { return }
        var updated = sessionContexts
        let item = updated.remove(at: fromIndex)
        updated.insert(item, at: toIndex)
        sessionContexts = updated

        if let gIdx = splitGroups.firstIndex(where: { $0.memberIDs.contains(fromID) && $0.memberIDs.contains(toID) }),
           let mFrom = splitGroups[gIdx].memberIDs.firstIndex(of: fromID),
           let mTo = splitGroups[gIdx].memberIDs.firstIndex(of: toID)
        {
            let mItem = splitGroups[gIdx].memberIDs.remove(at: mFrom)
            splitGroups[gIdx].memberIDs.insert(mItem, at: mTo)
        }
    }
}

/// Splits as plain data: which tabs share a split, by ID. Every tab can
/// join any split, whichever server it is connected to.
public extension Array where Element == TerminalManager.SplitGroup {
    func group(containing id: UUID) -> TerminalManager.SplitGroup? {
        first { $0.memberIDs.contains(id) }
    }

    /// Puts `newID` next to `anchorID` (after it, or before it), taking it
    /// out of any split it was in. The anchor's split takes `orientation`;
    /// when the anchor is on its own, the two start a new split.
    mutating func group(
        anchorID: UUID,
        newID: UUID,
        orientation: TerminalManager.SplitOrientation,
        insertBeforeAnchor: Bool = false
    ) {
        guard anchorID != newID else { return }
        removeMember(newID)
        if let idx = firstIndex(where: { $0.memberIDs.contains(anchorID) }) {
            var group = self[idx]
            group.orientation = orientation
            if let anchorPos = group.memberIDs.firstIndex(of: anchorID) {
                group.memberIDs.insert(newID, at: insertBeforeAnchor ? anchorPos : anchorPos + 1)
            } else {
                group.memberIDs.append(newID)
            }
            self[idx] = group
        } else {
            let members = insertBeforeAnchor ? [newID, anchorID] : [anchorID, newID]
            append(TerminalManager.SplitGroup(memberIDs: members, orientation: orientation))
        }
    }

    /// Takes `id` out of its split; a split left with one tab ends.
    mutating func removeMember(_ id: UUID) {
        for idx in indices.reversed() {
            self[idx].memberIDs.removeAll { $0 == id }
            if self[idx].memberIDs.count < 2 {
                remove(at: idx)
            }
        }
    }

    /// The tabs shown with `focusedID` in front, in split order, among the
    /// tabs still open (`openIDs`): its split, or the tab alone.
    func visiblePaneIDs(focusedID: UUID, openIDs: [UUID]) -> [UUID] {
        if let group = group(containing: focusedID) {
            let open = Set(openIDs)
            let matched = group.memberIDs.filter { open.contains($0) }
            if matched.count >= 2 { return matched }
        }
        return [focusedID]
    }
}

/// Where the panes of a grid split go: as many columns as rows, or one
/// more column, filled row by row; the last row may be short, and its
/// panes share its width.
public enum SplitGrid {
    /// The columns and rows for `count` panes: 2 → 2×1, 3 and 4 → 2×2,
    /// 5 and 6 → 3×2, 7 to 9 → 3×3.
    public static func dimensions(for count: Int) -> (columns: Int, rows: Int) {
        guard count > 0 else { return (0, 0) }
        var columns = 1
        while columns * columns < count { columns += 1 }
        let rows = (count + columns - 1) / columns
        return (columns, rows)
    }

    /// `items` cut into the grid's rows, in order.
    public static func rows<T>(_ items: [T]) -> [[T]] {
        let columns = dimensions(for: items.count).columns
        guard columns > 0 else { return [] }
        return stride(from: 0, to: items.count, by: columns).map {
            Array(items[$0 ..< Swift.min($0 + columns, items.count)])
        }
    }
}
