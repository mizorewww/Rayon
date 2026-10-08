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
    /// Hover tooltip describing the current state and what a click does next.
    var tooltip: String {
        switch self {
        case .none:
            return "Machine details are visible. Click to hide addresses."
        case .sensitive:
            return "Addresses are hidden. Click to hide all details."
        case .all:
            return "All machine details are hidden. Click to show everything."
        }
    }
}
