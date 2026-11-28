//
//  AppSetting.swift
//  RayonModule
//
//  A setting in a view (or menu commands): `@AppSetting(AppSettings.x) var x`
//  reads it, sets it through its key, and draws again when it changes,
//  wherever the change came from. In Settings a change made through it goes
//  on the window's undo stack, beside the terminal's settings, so ⌘Z undoes
//  the change in front rather than reaching back to an older one elsewhere.
//  Elsewhere (a terminal's zoom, an editor's Wrap Lines) it does not: those
//  are not edits for ⌘Z to take back among the text typed in that window.
//

import Combine
import SwiftUI

@MainActor @propertyWrapper
public struct AppSetting<Value: Codable & Equatable & Sendable>: DynamicProperty {
    @ObservedObject private var observer: SettingObserver<Value>
    @Environment(\.undoManager) private var windowUndoManager
    @Environment(\.registersSettingUndo) private var registersUndo

    public init(_ key: SettingKey<Value>) {
        observer = SettingObserver.shared(key)
    }

    private var undoManager: UndoManager? {
        registersUndo ? windowUndoManager : nil
    }

    public var wrappedValue: Value {
        get { observer.value }
        nonmutating set { observer.set(newValue, undoManager: undoManager) }
    }

    public var projectedValue: Binding<Value> {
        let observer = observer
        let undoManager = undoManager
        return Binding(get: { observer.value }, set: { observer.set($0, undoManager: undoManager) })
    }
}

public extension EnvironmentValues {
    /// Whether changes made through `@AppSetting` go on the window's undo
    /// stack: true in Settings only.
    @Entry var registersSettingUndo = false
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

    /// Sets it, and on `undoManager` how to set it back; undoing that
    /// registers the redo.
    func set(_ newValue: Value, undoManager: UndoManager?) {
        let old = value
        guard newValue != old else { return }
        set(newValue)
        undoManager?.registerUndo(withTarget: self) { observer in
            MainActor.assumeIsolated { observer.set(old, undoManager: undoManager) }
        }
    }
}

/// Generic types cannot keep a static, so the observers live here.
@MainActor
private enum SettingObservers {
    static var all: [String: AnyObject] = [:]
}
