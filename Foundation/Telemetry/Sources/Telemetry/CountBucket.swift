//
//  CountBucket.swift
//  Telemetry
//

import Foundation

/// A count rounded down to the lower bound of its bucket:
/// 0 / 1 / 2–5 / 6–20 / 21–100 / more than 100.
public enum CountBucket: Int, Codable, CaseIterable, Sendable {
    case zero = 0
    case one = 1
    case few = 2
    case some = 6
    case many = 21
    case lots = 101

    public init(_ count: Int) {
        self = switch count {
        case ..<1: .zero
        case 1: .one
        case 2 ... 5: .few
        case 6 ... 20: .some
        case 21 ... 100: .many
        default: .lots
        }
    }
}
