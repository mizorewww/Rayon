//
//  VNCDiscovery.swift
//  RayonModule
//
//  Screen-sharing hosts on the local network: Bonjour's `_rfb._tcp`, which
//  macOS Screen Sharing and most VNC servers advertise. Each service is
//  resolved to its host name (`MacbookProM2.local`), which outlives the
//  address DHCP hands out.
//

import dnssd
import Foundation
import Network

/// One advertised screen-sharing service.
public struct VNCDiscoveredHost: Identifiable, Equatable, Sendable {
    /// The service name, unique on the network ("Macbook_Pro_M2").
    public var id: String { name }
    public var name: String
    /// The resolved host name without the trailing dot; empty until resolved.
    public var hostName: String
    public var port: Int

    /// The service name as people write it: underscores read as spaces.
    public var displayName: String {
        name.replacingOccurrences(of: "_", with: " ")
    }

    /// Whether a saved server already points at this host.
    public func matches(_ machine: RDMachine) -> Bool {
        guard machine.remoteDesktopProtocol == .vnc, !hostName.isEmpty else { return false }
        let address = machine.remoteAddress.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return address == hostName.lowercased() && (Int(machine.vncPort) ?? 5900) == port
    }

    /// A VNC server for this host. A Mac asks for an account (Apple
    /// authentication), so the user name and password are left to the editor.
    public func makeMachine() -> RDMachine {
        var machine = RDMachine(remoteAddress: hostName, remotePort: "22", name: displayName)
        machine.remoteDesktopProtocol = .vnc
        machine.vncPort = String(port)
        return machine
    }
}

/// Browses `_rfb._tcp` while something shows the result: an `NWBrowser`
/// lists the services, and each is resolved to its host name and port
/// with `DNSServiceResolve` (Network.framework resolves to addresses only).
/// Start and stop from the main actor; every callback lands there.
@MainActor
public final class VNCDiscovery: ObservableObject {
    public static let shared = VNCDiscovery()

    @Published public private(set) var hosts: [VNCDiscoveredHost] = []
    /// Why browsing stopped, e.g. local network access was refused.
    @Published public private(set) var failure: String?
    /// True for the first seconds of browsing, while nothing found yet
    /// means little.
    @Published public private(set) var isSearching = false

    private var browser: NWBrowser?
    /// Services being resolved or resolved, by service name.
    private var resolutions: [String: Resolution] = [:]
    private var watchers = 0

    /// Starts browsing for the first watcher.
    public func start() {
        watchers += 1
        guard browser == nil else { return }
        failure = nil
        let browser = NWBrowser(for: .bonjour(type: "_rfb._tcp", domain: "local."), using: .tcp)
        browser.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.browserChanged(state) }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated { self?.resultsChanged(results) }
        }
        browser.start(queue: .main)
        self.browser = browser
        isSearching = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            self?.isSearching = false
        }
    }

    /// Stops once the last watcher is gone.
    public func stop() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        browser?.cancel()
        browser = nil
        resolutions.values.forEach { $0.cancel() }
        resolutions.removeAll()
        hosts.removeAll()
    }

    private func browserChanged(_ state: NWBrowser.State) {
        // PolicyDenied: no local network access, or the service type is
        // not declared in NSBonjourServices. Other waits (no network yet)
        // resolve themselves.
        let denied = NWError.dns(DNSServiceErrorType(kDNSServiceErr_PolicyDenied))
        switch state {
        case .waiting(denied), .failed(denied):
            failure = String(localized: "Rayon may not look on the local network. Allow it in System Settings › Privacy & Security › Local Network.", bundle: .module)
        case let .failed(error):
            failure = String(localized: "Could not look for screen-sharing hosts (\(error.localizedDescription)).", bundle: .module)
        default:
            return
        }
        browser?.cancel()
        browser = nil
    }

    private func resultsChanged(_ results: Set<NWBrowser.Result>) {
        var services: [String: NWBrowser.Result] = [:]
        for result in results {
            if case let .service(name, _, _, _) = result.endpoint { services[name] = result }
        }
        for name in resolutions.keys where services[name] == nil {
            resolutions.removeValue(forKey: name)?.cancel()
            hosts.removeAll { $0.name == name }
        }
        for (name, result) in services where resolutions[name] == nil {
            guard case let .service(_, type, domain, interface) = result.endpoint else { continue }
            resolutions[name] = Resolution(
                name: name, type: type, domain: domain,
                interfaceIndex: interface.map { UInt32($0.index) } ?? 0
            ) { [weak self] hostName, port in
                self?.resolved(name: name, hostName: hostName, port: port)
            }
        }
    }

    private func resolved(name: String, hostName: String, port: Int) {
        guard port > 0 else { return }
        let host = VNCDiscoveredHost(
            name: name,
            hostName: hostName.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
            port: port
        )
        hosts.removeAll { $0.name == host.name }
        hosts.append(host)
        hosts.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// One `DNSServiceResolve`, answering on the main queue until cancelled.
@MainActor
private final class Resolution {
    typealias Handler = @MainActor (_ hostName: String, _ port: Int) -> Void

    private var reference: DNSServiceRef?
    private let handler: Handler

    init(name: String, type: String, domain: String, interfaceIndex: UInt32, handler: @escaping Handler) {
        self.handler = handler
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = DNSServiceResolve(&reference, 0, interfaceIndex, name, type, domain, { _, _, _, error, _, hostTarget, port, _, _, context in
            guard error == kDNSServiceErr_NoError, let hostTarget, let context else { return }
            let hostName = String(cString: hostTarget)
            MainActor.assumeIsolated {
                let resolution = Unmanaged<Resolution>.fromOpaque(context).takeUnretainedValue()
                resolution.handler(hostName, Int(UInt16(bigEndian: port)))
            }
        }, context)
        guard status == kDNSServiceErr_NoError, let reference else {
            self.reference = nil
            return
        }
        DNSServiceSetDispatchQueue(reference, .main)
    }

    /// Stops resolving. Call before releasing: the callback holds `self`
    /// unretained, and deallocating the reference on the callback queue
    /// guarantees no further callback.
    func cancel() {
        if let reference { DNSServiceRefDeallocate(reference) }
        reference = nil
    }
}
