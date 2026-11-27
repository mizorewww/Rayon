//
//  Storage+Column.swift
//  RayonModule
//
//  How the model types that are not SQLite primitives are kept in a column.
//

import Foundation
@preconcurrency import WCDBSwift

extension UUID: @retroactive ColumnCodable {
    public init?(with value: Value) {
        self.init(uuidString: value.stringValue)
    }

    public func archivedValue() -> Value {
        Value(uuidString)
    }

    public static var columnType: ColumnType { .text }
}

/// An enum kept by its raw string.
protocol StringColumn: RawRepresentable<String>, ColumnCodable {}

extension StringColumn {
    public init?(with value: Value) {
        self.init(rawValue: value.stringValue)
    }

    public func archivedValue() -> Value {
        Value(rawValue)
    }

    public static var columnType: ColumnType { .text }
}

extension Date {
    /// The date at millisecond precision, the precision dates are compared at
    /// when records from other devices are merged.
    var wholeMilliseconds: Date {
        Date(timeIntervalSince1970: (timeIntervalSince1970 * 1000).rounded() / 1000)
    }

    var millisecondsSince1970: Int64 {
        Int64((timeIntervalSince1970 * 1000).rounded())
    }
}

extension RDMachine.Transport: StringColumn {}
extension RDMachine.RemoteDesktopProtocolType: StringColumn {}
