//
//  RDPortForward+Presentation.swift
//  RayonModule
//
//  The words a forward is shown with: its kind, its target and the ssh
//  command it stands for, complete or not. Shared by the macOS and iOS
//  lists and editors.
//

import Foundation

public extension RDPortForward.ForwardOrientation {
    /// The kind, as a row's tag.
    var label: String {
        switch self {
        case .listenLocal: return String(localized: "Listen local", bundle: .module)
        case .listenRemote: return String(localized: "Listen remote", bundle: .module)
        case .dynamicSOCKS: return "SOCKS5 (-D)"
        }
    }

    /// Where traffic goes, from `device` ("This Mac", "This iPhone").
    func flowDescription(device: String) -> String {
        switch self {
        case .listenLocal: return String(localized: "\(device) :port → server → target", bundle: .module)
        case .listenRemote: return String(localized: "Server :port → \(device.prefix(1).lowercased() + device.dropFirst()) → target", bundle: .module)
        case .dynamicSOCKS: return String(localized: "\(device) :port (SOCKS5) → server → any destination", bundle: .module)
        }
    }
}

public extension RDPortForward {
    /// host:port, or what a SOCKS proxy reaches instead.
    var targetLabel: String {
        if forwardOrientation == .dynamicSOCKS { return String(localized: "SOCKS5 proxy", bundle: .module) }
        return targetHost.isEmpty ? "—" : "\(targetHost):\(targetPort)"
    }

    /// The equivalent ssh command; while the forward is incomplete, the
    /// command with placeholders for what is missing.
    var commandPreview: String {
        if let command = getCommand() { return command }
        let bind = bindPort > 0 ? String(bindPort) : ""
        switch forwardOrientation {
        case .dynamicSOCKS:
            return "ssh -D \(bind.isEmpty ? "1080" : bind) <server>"
        case .listenLocal, .listenRemote:
            let flag = forwardOrientation == .listenLocal ? "-L" : "-R"
            let target = targetPort > 0 ? String(targetPort) : ""
            return "ssh \(flag) \(bind.isEmpty ? "port" : bind):\(targetHost.isEmpty ? "127.0.0.1" : targetHost):\(target.isEmpty ? "port" : target) <server>"
        }
    }
}
