//
//  RDMachine+Redacted.swift
//  Rayon (macOS)
//
//  Created by Lakr Aream on 2022/3/1.
//

import Foundation

public extension RDMachine {
    enum RedactedLevel: Int, Codable {
        case none = 0
        case sensitive = 1
        case all = 2
    }
}

public extension RDMachine.RedactedLevel {
    /// Hover tooltip describing the current redaction state.
    var tooltip: String {
        switch self {
        case .none:
            return "Redaction: server names and addresses are visible"
        case .sensitive:
            return "Redaction: server addresses are hidden"
        case .all:
            return "Redaction: server names and addresses are hidden"
        }
    }
}
