//
//  RemoteFileComparator.swift
//  RayonModule
//
//  The order the file lists show a folder in: by one column, folders on top.
//

import Foundation

public struct RemoteFileComparator: SortComparator, Hashable, Sendable {
    public enum Field: String, CaseIterable, Hashable, Sendable {
        case name
        case size
        case modified
        case kind
    }

    public var field: Field
    public var order: SortOrder

    public init(_ field: Field, order: SortOrder = .forward) {
        self.field = field
        self.order = order
    }

    public func compare(_ lhs: FileTransferContext.RemoteFile, _ rhs: FileTransferContext.RemoteFile) -> ComparisonResult {
        // Folders stay on top whichever way a column sorts, as in Finder's
        // "Keep folders on top".
        if lhs.isFolder != rhs.isFolder { return lhs.isFolder ? .orderedAscending : .orderedDescending }
        var result: ComparisonResult = switch field {
        case .name: .orderedSame
        case .size: Self.compare(lhs.fstat.size ?? 0, rhs.fstat.size ?? 0)
        case .modified: Self.compare(lhs.fstat.modificationDate ?? .distantPast, rhs.fstat.modificationDate ?? .distantPast)
        case .kind: lhs.kind.localizedStandardCompare(rhs.kind)
        }
        // Rows that tie on the column follow their names, as Finder sorts them.
        if result == .orderedSame { result = lhs.name.localizedStandardCompare(rhs.name) }
        guard order == .reverse else { return result }
        switch result {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }

    private static func compare<Value: Comparable>(_ lhs: Value, _ rhs: Value) -> ComparisonResult {
        lhs < rhs ? .orderedAscending : (lhs > rhs ? .orderedDescending : .orderedSame)
    }
}
