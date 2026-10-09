//
//  StatusItem.swift
//  Rayon (macOS)
//
//  Created by Lakr Aream on 2022/3/1.
//
//  The menu bar extra per server: the run cat (frame rate follows CPU load, crash
//  frame when unreachable) and a popover with CPU / Memory / RX / TX, Graphics and
//  Disks, then Terminal, Monitor and Open Rayon.
//

import AppKit
import Combine
import MachineStatus
import MachineStatusView
import RayonModule
import SwiftUI

class MenubarStatusItem: NSObject, Identifiable {
    let id: UUID = .init()

    let machine: RDMachine
    let identity: RDIdentity
    var eventMonitor: EventMonitor?
    var popover: NSPopover
    let session: MonitorSession

    var loopContinue: Bool = true
    var cancellables = Set<AnyCancellable>()

    @MainActor init(machine: RDMachine, identity: RDIdentity, session: MonitorSession? = nil) {
        self.machine = machine
        self.identity = identity
        self.session = session ?? MonitorSession(machine: machine, identity: identity)

        let buildPopover = NSPopover()
        buildPopover.behavior = .transient
        popover = buildPopover

        super.init()

        let contentView = MenubarPopoverView(session: self.session) { [weak self] in
            self?.closeThisItem()
        } dismiss: { [weak self] in
            self?.popover.performClose(nil)
        }
        .environmentObject(RayonStore.shared)
        buildPopover.contentViewController = NSHostingController(rootView: contentView)

        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown], handler: { [self] event in
            // AppKit delivers global event-monitor callbacks on the main thread.
            MainActor.assumeIsolated { mouseEventHandler(event) }
        })

        observeSession()
        beginFrameLoop()

        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover(sender:))
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.toolTip = machine.name
    }

    deinit {
        debugPrint("\(self) \(#function)")
    }

    let accessLock = NSLock()

    let statusItem: NSStatusItem = NSStatusBar
        .system
        .statusItem(withLength: NSStatusItem.variableLength)

    let frames: [NSImage] = {
        [
            NSImage(named: "cat_frame_0"),
            NSImage(named: "cat_frame_1"),
            NSImage(named: "cat_frame_2"),
            NSImage(named: "cat_frame_3"),
            NSImage(named: "cat_frame_4"),
        ]
        .compactMap { $0 }
    }()

    var currentImageIndex: Int = 0
    enum CatSpeed: TimeInterval {
        case light = 0.05
        case fast = 0.1
        case run = 0.25
        case walk = 0.5
        case hang = 1
        case broken = -1
    }

    var catSpeed = CatSpeed.broken

    @MainActor @objc func togglePopover(sender: AnyObject) {
        if popover.isShown {
            hidePopover(sender)
        } else {
            showPopover(sender)
        }
    }

    func showPopover(_: AnyObject) {
        if let statusBarButton = statusItem.button {
            popover.show(relativeTo: statusBarButton.bounds, of: statusBarButton, preferredEdge: NSRectEdge.maxY)
            eventMonitor?.start()
        }
    }

    @MainActor func hidePopover(_ sender: AnyObject) {
        popover.performClose(sender)
        eventMonitor?.stop()
    }

    @MainActor func mouseEventHandler(_ event: NSEvent?) {
        if popover.isShown, let event = event {
            hidePopover(event)
        }
    }

    func closeThisItem() {
        popover.close()
        session.shutdown()
        loopContinue = false
        eventMonitor = nil
        cancellables.removeAll()
        NSStatusBar.system.removeStatusItem(statusItem)
        MenubarTool.shared.remove(menubarItem: id)
    }
}

/// The popover for one server: the same cards as its Monitor page, in one column.
struct MenubarPopoverView: View {
    @ObservedObject var session: MonitorSession
    @EnvironmentObject var store: RayonStore
    let remove: () -> Void
    let dismiss: () -> Void

    static let width: CGFloat = 380

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, RX.Space.s4)
                .padding(.vertical, RX.Space.s3)
            Hairline()
            ScrollView {
                VStack(spacing: RX.Space.s3) {
                    if session.phase == .connected, session.status.hasData {
                        SystemCard(session: session)
                        ProcessorCard(session: session)
                        MemoryCard(session: session)
                        HStack(spacing: RX.Space.s3) {
                            ThroughputCard(session: session, direction: .receive, height: 128)
                            ThroughputCard(session: session, direction: .transmit, height: 128)
                        }
                        NetworkCard(session: session)
                        DiskCard(session: session)
                        GraphicsCard(session: session)
                    } else {
                        MonitorPlaceholder(session: session)
                    }
                }
                .padding(RX.Space.s3)
            }
            .frame(height: 560)
        }
        .frame(width: Self.width)
    }

    /// Name and system facts on the left; the server's tools as symbols on the right.
    var header: some View {
        let system = session.status.system
        // The hostname only when it says something the name doesn't.
        let hostname = system.hostname == session.machine.name ? "" : system.hostname
        let facts = [hostname, system.releaseName, system.uptimeSec > 0 ? "up \(RXFormat.duration(system.uptimeSec))" : ""]
            .filter { !$0.isEmpty }
        return HStack(alignment: .center, spacing: RX.Space.s2) {
            VStack(alignment: .leading, spacing: 2) {
                RedactableText(session.machine.name, redacted: store.machineRedacted == .all)
                    .font(.rxBodyStrong)
                    .foregroundStyle(.rxInk)
                    .lineLimit(1)
                if !facts.isEmpty {
                    Text(facts.joined(separator: " · "))
                        .font(.rxHelp)
                        .foregroundStyle(.rxInkSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: RX.Space.s2)
            ForEach(ServerTool.allCases) { tool in
                RXIconButton(tool.help, systemImage: tool.systemImage, kind: .plain) {
                    dismiss()
                    openMainWindow()
                    tool.show(session.machine.id)
                }
            }
            Hairline(vertical: true)
                .frame(height: 16)
            RXIconButton("Remove from Menu Bar", systemImage: "xmark", kind: .plain, action: remove)
        }
    }

    func openMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
