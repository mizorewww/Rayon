//
//  PreviewSSH.swift
//  Rayon
//
//  Debug builds: `RAYON_PREVIEW_SSH=user:password@host:port` saves "Preview
//  SSH", a server that signs in with that password, and
//  `RAYON_PREVIEW_SSH_HOSTKEY=<type> <base64>` trusts its host key, so QA
//  reaches a local test sshd without typing into the app.
//

#if DEBUG
    import Foundation
    import RayonModule
    import RayonSSH

    @MainActor
    enum PreviewSSH {
        static let machineID = UUID(uuidString: "C0FFEE00-0000-4000-8000-0000000055A1")!
        static let identityID = UUID(uuidString: "C0FFEE00-0000-4000-8000-0000000055A2")!

        static func seed() {
            let environment = ProcessInfo.processInfo.environment
            guard let value = environment["RAYON_PREVIEW_SSH"],
                  let at = value.lastIndex(of: "@"),
                  let colon = value[..<at].firstIndex(of: ":"),
                  let portColon = value[value.index(after: at)...].lastIndex(of: ":")
            else { return }
            let host = String(value[value.index(after: at) ..< portColon])
            let port = String(value[value.index(after: portColon)...])
            let identity = RDIdentity(id: identityID, username: String(value[..<colon]), password: String(value[value.index(after: colon) ..< at]))
            _ = RayonStore.shared.save(identity)
            _ = RayonStore.shared.save(RDMachine(id: machineID, remoteAddress: host, remotePort: port, name: "Preview SSH", associatedIdentity: identityID))
            if let parts = environment["RAYON_PREVIEW_SSH_HOSTKEY"]?.split(separator: " "), parts.count == 2,
               let key = Data(base64Encoded: String(parts[1])), let portNumber = Int(port)
            {
                KnownHosts.shared.trust(SSHHostKey(type: String(parts[0]), key: key), host: host, port: portNumber)
            }
        }
    }
#endif
