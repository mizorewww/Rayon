//
//  AppSetting.swift
//  RayonModule
//
//  A setting in a view (or menu commands): `@AppSetting(AppSettings.x) var x`
//  reads it, sets it through its key, and draws again when it changes,
//  wherever the change came from.
//

import Combine
import SwiftUI

@MainActor @propertyWrapper
public struct AppSetting<Value: Codable & Equatable & Sendable>: DynamicProperty {
    @ObservedObject private var observer: SettingObserver<Value>

    public init(_ key: SettingKey<Value>) {
        observer = SettingObserver.shared(key)
    }

    public var wrappedValue: Value {
        get { observer.value }
        nonmutating set { observer.set(newValue) }
    }

    public var projectedValue: Binding<Value> {
        let observer = observer
        return Binding(get: { observer.value }, set: { observer.set($0) })
    }
}

/// One per setting, shared by every view that shows it.
@MainActor
final class SettingObserver<Value: Codable & Equatable & Sendable>: ObservableObject {
    private static var observers: [String: AnyObject] {
        get { SettingObservers.all }
        set { SettingObservers.all = newValue }
    }

    static func shared(_ key: SettingKey<Value>) -> SettingObserver<Value> {
        if let observer = observers[key.key] as? SettingObserver<Value> {
            return observer
        }
        let observer = SettingObserver(key)
        observers[key.key] = observer
        return observer
    }

    let key: SettingKey<Value>
    @Published private(set) var value: Value
    private var subscription: AnyCancellable?

    private init(_ key: SettingKey<Value>) {
        self.key = key
        value = key.value
        subscription = key.publisher.sink { [weak self] value in
            MainActor.assumeIsolated {
                guard let self, self.value != value else { return }
                self.value = value
            }
        }
    }

    func set(_ newValue: Value) {
        guard newValue != value else { return }
        value = newValue
        key.set(newValue)
    }
}

/// Generic types cannot keep a static, so the observers live here.
@MainActor
private enum SettingObservers {
    static var all: [String: AnyObject] = [:]
}
