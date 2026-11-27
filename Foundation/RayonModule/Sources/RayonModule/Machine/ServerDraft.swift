//
//  ServerDraft.swift
//  RayonModule
//
//  The server editor's fields and the checks made before saving, shared by
//  the Mac and iOS editors so both refuse the same input.
//

import Foundation

/// Editable copy of a server.
public struct ServerDraft: Equatable, Sendable {
    public var name = ""
    public var address = ""
    public var port = "22"
    public var transport: RDMachine.Transport = .direct
    public var proxyJumpMachineID: RDMachine.ID?
    public var serviceTokenID = ""
    public var serviceTokenSecret = ""
    public var identity: RDIdentity.ID?
    public var sshUsername = ""
    /// The folder's name; empty for the default folder.
    public var folder = ""
    public var startFolder = "/"
    public var comment = ""
    public var remoteDesktopProtocol: RDMachine.RemoteDesktopProtocolType = .none
    public var vncPort = "5900"
    public var vncPassword = ""
    public var vncUsername = ""
    public var vncOverSSH = false
    public var vncShared = true
    public var uuDeviceID = ""
    public var uuAssistID = ""
    public var uuAssistCode = ""

    public init() {}

    public init(_ machine: RDMachine, folder: String) {
        name = machine.name
        address = machine.remoteAddress
        port = machine.remotePort.isEmpty ? "22" : machine.remotePort
        transport = machine.transport
        proxyJumpMachineID = machine.proxyJumpMachineID
        serviceTokenID = machine.cloudflareServiceTokenID
        serviceTokenSecret = machine.cloudflareServiceTokenSecret
        identity = machine.associatedIdentity
        sshUsername = machine.sshUsername
        self.folder = folder
        startFolder = machine.fileTransferLoginPath
        comment = machine.comment
        remoteDesktopProtocol = machine.remoteDesktopProtocol
        vncPort = machine.vncPort
        vncPassword = machine.vncPassword
        vncUsername = machine.vncUsername
        vncOverSSH = machine.vncOverSSH
        vncShared = machine.vncShared
        uuDeviceID = machine.uuDeviceID
        uuAssistID = machine.uuAssistID
        uuAssistCode = machine.uuAssistCode
    }

    /// Why the draft cannot be saved; the first problem in form order.
    public enum Problem: LocalizedError, Equatable, Sendable {
        case emptyAddress
        case invalidPort
        case noJumpServer
        case invalidVNCPort

        public var errorDescription: String? {
            switch self {
            case .emptyAddress: String(localized: "Enter the server's address.", bundle: .module)
            case .invalidPort: String(localized: "The port is a number from 1 to 65535.", bundle: .module)
            case .noJumpServer: String(localized: "Choose a jump server.", bundle: .module)
            case .invalidVNCPort: String(localized: "The VNC port is a number from 1 to 65535.", bundle: .module)
            }
        }
    }

    public var trimmedAddress: String {
        address.trimmingCharacters(in: .whitespaces)
    }

    public var portIsValid: Bool {
        Self.isPort(port)
    }

    /// An empty VNC port means the default, 5900.
    public var vncPortIsValid: Bool {
        vncPort.trimmingCharacters(in: .whitespaces).isEmpty || Self.isPort(vncPort)
    }

    public var problem: Problem? {
        if trimmedAddress.isEmpty { return .emptyAddress }
        if !portIsValid { return .invalidPort }
        if transport == .proxyJump, proxyJumpMachineID == nil { return .noJumpServer }
        if remoteDesktopProtocol == .vnc, !vncPortIsValid { return .invalidVNCPort }
        return nil
    }

    public var isValid: Bool {
        problem == nil
    }

    /// A TCP port: 1 through 65535, so "0" and "00" are refused.
    public static func isPort(_ text: String) -> Bool {
        guard let port = UInt16(text.trimmingCharacters(in: .whitespaces)) else { return false }
        return port > 0
    }

    /// `machine` with the draft's fields, keeping what the editors do not
    /// show; `folderId` is the folder `folder` names.
    public func apply(to machine: RDMachine, folderId: RDFolder.ID?) -> RDMachine {
        var result = machine
        result.remoteAddress = trimmedAddress
        result.remotePort = port.trimmingCharacters(in: .whitespaces)
        result.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? trimmedAddress : name
        result.folderId = folderId
        result.comment = comment
        result.associatedIdentity = identity
        result.sshUsername = sshUsername.trimmingCharacters(in: .whitespaces)
        result.fileTransferLoginPath = startFolder.isEmpty ? "/" : startFolder
        result.transport = transport
        result.proxyJumpMachineID = transport == .proxyJump ? proxyJumpMachineID : nil
        let cloudflare = transport == .cloudflareAccess
        result.cloudflareServiceTokenID = cloudflare ? serviceTokenID.trimmingCharacters(in: .whitespaces) : ""
        result.cloudflareServiceTokenSecret = cloudflare ? serviceTokenSecret.trimmingCharacters(in: .whitespaces) : ""
        result.remoteDesktopProtocol = remoteDesktopProtocol
        result.vncPort = vncPort.trimmingCharacters(in: .whitespaces)
        result.vncPassword = vncPassword
        result.vncUsername = vncUsername.trimmingCharacters(in: .whitespaces)
        result.vncOverSSH = vncOverSSH
        result.vncShared = vncShared
        result.uuDeviceID = uuDeviceID.trimmingCharacters(in: .whitespaces)
        result.uuAssistID = uuAssistID.trimmingCharacters(in: .whitespaces)
        result.uuAssistCode = uuAssistCode
        return result
    }
}
