//
//  RDPortForward.swift
//
//
//  Created by Lakr Aream on 2022/3/10.
//

import Foundation
@preconcurrency import WCDBSwift

public struct RDPortForward: StoredRecord {
    public static let tableName = "PortForward"

    public enum ForwardOrientation: String, Codable, CaseIterable, Sendable, StringColumn {
        case listenLocal = "Local"
        case listenRemote = "Remote"
        case dynamicSOCKS = "Dynamic"
    }

    public var id = UUID()
    public var forwardOrientation: ForwardOrientation = .listenLocal
    public var bindPort = 0
    /// Where the forward leads; unused by a dynamic (SOCKS) forward.
    public var targetHost = ""
    public var targetPort = 0
    public var usingMachine: RDMachine.ID?

    public var modified = Date()
    public var removed = false
    public var secrets = NoSecrets()

    public init(
        id: UUID = .init(),
        forwardOrientation: ForwardOrientation = .listenLocal,
        bindPort: Int = 0,
        targetHost: String = "",
        targetPort: Int = 0,
        usingMachine: RDMachine.ID? = nil
    ) {
        self.id = id
        self.forwardOrientation = forwardOrientation
        self.bindPort = bindPort
        self.targetHost = targetHost
        self.targetPort = targetPort
        self.usingMachine = usingMachine
    }

    public enum CodingKeys: String, CodingTableKey {
        public typealias Root = RDPortForward
        public static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(id, isPrimary: true)
            BindColumnConstraint(modified, isNotNull: true)
            BindColumnConstraint(removed, isNotNull: true, defaultTo: false)
        }

        case id
        case forwardOrientation
        case bindPort
        case targetHost
        case targetPort
        case usingMachine
        case modified
        case removed
    }

    public var forwardReversed: Bool {
        get { forwardOrientation == .listenRemote }
        set { forwardOrientation = newValue ? .listenRemote : .listenLocal }
    }

    /// Whether everything its kind of forward needs is filled in: a port to
    /// listen on and a server, and for a local or remote forward where it
    /// leads. A dynamic (SOCKS) forward has no target.
    public var isComplete: Bool {
        guard (1 ... 65535).contains(bindPort), usingMachine != nil else { return false }
        switch forwardOrientation {
        case .dynamicSOCKS:
            return true
        case .listenLocal, .listenRemote:
            return !targetHost.isEmpty && (1 ... 65535).contains(targetPort)
        }
    }

    /// Complete, and its server still exists.
    public func isValid() -> Bool {
        guard isComplete, let machine = usingMachine else { return false }
        return RayonStore.workerMachine(for: machine) != nil
    }

    public func getMachineName() -> String? {
        usingMachine.flatMap { RayonStore.workerMachine(for: $0) }?.name
    }

    public func shortDescription() -> String {
        guard isValid() else {
            return "Invalid Forward"
        }
        switch forwardOrientation {
        case .listenLocal:
            return "localhost:\(bindPort) -\(getMachineName() ?? "Unknown")-> \(targetHost):\(targetPort)"
        case .listenRemote:
            return "\(getMachineName() ?? "Unknown"):\(bindPort) -localhost-> \(targetHost):\(targetPort)"
        case .dynamicSOCKS:
            return "SOCKS5 localhost:\(bindPort) -\(getMachineName() ?? "Unknown")-> *"
        }
    }

    public func getCommand() -> String? {
        guard isComplete, let using = usingMachine,
              let machine = RayonStore.workerMachine(for: using)
        else {
            return nil
        }
        let target = machine.getCommand(insertLeadingSSH: false)
        switch forwardOrientation {
        case .listenLocal:
            return "ssh -L \(bindPort):\(targetHost):\(targetPort) \(target)"
        case .listenRemote:
            return "ssh -R \(bindPort):\(targetHost):\(targetPort) \(target)"
        case .dynamicSOCKS:
            return "ssh -D \(bindPort) \(target)"
        }
    }
}
