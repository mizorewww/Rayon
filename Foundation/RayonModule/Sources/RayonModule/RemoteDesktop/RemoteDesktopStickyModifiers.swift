//
//  RemoteDesktopStickyModifiers.swift
//  RayonModule
//
//  The modifier keys of the iOS keyboard bar, which a finger cannot hold
//  while it types: tapped, one holds for the next key; tapped twice
//  quickly, it stays down until tapped again. As in libghostty-spm's
//  terminal accessory bar.
//

import Foundation

struct RemoteDesktopStickyModifiers: Equatable {
    enum Modifier: CaseIterable, Sendable {
        case control, option, command, shift

        /// The key it holds down on the host.
        var stroke: RemoteDesktopKeyStroke {
            switch self {
            case .control: RemoteDesktopSpecialKeys.control
            case .option: RemoteDesktopSpecialKeys.alt
            case .command: RemoteDesktopSpecialKeys.super
            case .shift: RemoteDesktopSpecialKeys.shift
            }
        }
    }

    enum Activation: Equatable, Sendable {
        /// Up.
        case inactive
        /// Down for the next key.
        case armed
        /// Down until tapped again.
        case locked
    }

    static let doubleTapInterval: TimeInterval = 0.3

    private var activations: [Modifier: Activation] = [:]
    private var lastTap: [Modifier: TimeInterval] = [:]

    subscript(modifier: Modifier) -> Activation {
        activations[modifier] ?? .inactive
    }

    /// The modifiers down now, in a fixed order.
    var active: [Modifier] {
        Modifier.allCases.filter { self[$0] != .inactive }
    }

    /// A tap on a modifier's key, at `time` (seconds, any clock). Returns
    /// its new activation.
    @discardableResult
    mutating func tap(_ modifier: Modifier, at time: TimeInterval) -> Activation {
        let next: Activation = switch self[modifier] {
        case .inactive: .armed
        case .armed: time - (lastTap[modifier] ?? -.infinity) < Self.doubleTapInterval ? .locked : .inactive
        case .locked: .inactive
        }
        activations[modifier] = next
        lastTap[modifier] = time
        return next
    }

    /// A key was sent: the armed modifiers let go. Returns them.
    mutating func consume() -> [Modifier] {
        let armed = Modifier.allCases.filter { self[$0] == .armed }
        for modifier in armed { activations[modifier] = .inactive }
        return armed
    }

    /// Lets go of every modifier. Returns those that were down.
    mutating func reset() -> [Modifier] {
        let down = active
        activations = [:]
        return down
    }
}
