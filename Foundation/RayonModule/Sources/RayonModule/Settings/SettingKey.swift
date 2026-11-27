//
//  SettingKey.swift
//  RayonModule
//
//  A setting as ConfigurableKit keeps it: its key, its value while the user
//  has not chosen one, and how far it may travel. Every setting is declared
//  once, in `AppSettings`; code reads and writes it through its key and
//  hears its changes, whoever made them (a page, iCloud, a backup), from
//  `publisher`.
//

import Combine
import ConfigurableKit
import Foundation

/// How far a setting travels.
public enum SettingScope: Sendable {
    /// To every device with iCloud sync, and into a settings backup.
    case synced
    /// Into a settings backup, never through iCloud: it fits one device,
    /// as a font size fits its screen.
    case device
    /// Nowhere: neither iCloud nor a backup carries it off this device.
    case deviceLocal
}

/// What sync and backups need of a setting, whatever its value's type.
public protocol AnySettingKey: Sendable {
    var key: String { get }
    var scope: SettingScope { get }
}

public struct SettingKey<Value: Codable & Equatable & Sendable>: AnySettingKey {
    public let key: String
    public let defaultValue: Value
    public let scope: SettingScope

    public init(_ key: String, default defaultValue: Value, scope: SettingScope) {
        self.key = key
        self.defaultValue = defaultValue
        self.scope = scope
    }

    public var value: Value {
        ConfigurableKit.value(forKey: key, defaultValue: defaultValue)
    }

    public func set(_ value: Value) {
        ConfigurableKit.set(value: value, forKey: key)
    }

    /// The value now, then each change, on the main queue.
    public var publisher: AnyPublisher<Value, Never> {
        ConfigurableKit.publisher(forKey: key, type: Value.self)
            .map { [defaultValue] in $0 ?? defaultValue }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}
