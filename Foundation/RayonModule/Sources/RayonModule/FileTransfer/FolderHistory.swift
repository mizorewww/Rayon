//
//  FolderHistory.swift
//  RayonModule
//
//  The folders Files has shown, for Back and Forward, as in a browser:
//  going somewhere new forgets what was ahead, and Back and Forward
//  only move along what is there.
//

import Foundation

public struct FolderHistory: Equatable, Sendable {
    /// The folders before the current one, the latest last.
    public private(set) var back: [String] = []
    /// The folders after the current one, the nearest last.
    public private(set) var forward: [String] = []

    /// The most folders kept on either side; the oldest go first.
    public static let limit = 100

    public init() {}

    public var canGoBack: Bool { !back.isEmpty }
    public var canGoForward: Bool { !forward.isEmpty }

    /// Going from `current` to a new folder: `current` can be gone back to,
    /// and what was ahead is forgotten. Staying in the same folder, as a
    /// reload does, changes nothing.
    public mutating func visit(from current: String, to destination: String) {
        guard current != destination else { return }
        back.append(current)
        if back.count > Self.limit { back.removeFirst(back.count - Self.limit) }
        forward.removeAll()
    }

    /// The folder before `current`, with `current` kept ahead of it; nil when there is none.
    public mutating func goBack(from current: String) -> String? {
        guard let destination = back.popLast() else { return nil }
        forward.append(current)
        if forward.count > Self.limit { forward.removeFirst(forward.count - Self.limit) }
        return destination
    }

    /// The folder after `current`, with `current` kept behind it; nil when there is none.
    public mutating func goForward(from current: String) -> String? {
        guard let destination = forward.popLast() else { return nil }
        back.append(current)
        if back.count > Self.limit { back.removeFirst(back.count - Self.limit) }
        return destination
    }
}
