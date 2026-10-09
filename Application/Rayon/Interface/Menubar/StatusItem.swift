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

    @MainActor init(machine: RDMachine, identity: RDIdentity) {
        self.machine = machine
        self.identity = identity
        session = MonitorSession(machine: machine, identity: identity)

        let buildPopover = NSPopover()
        buildPopover.behavior = .transient
        popover = buildPopover

        super.init()

        let contentView = MenubarPopoverView(session: session) { [weak self] in
            self?.closeThisItem()
        } dismiss: { [weak self] in
            self?.popover.performClose(nil)
        }
        .environmentObject(RayonStore.shared)
        .frame(width: 340)
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

/// The popover for one server.
struct MenubarPopoverView: View {
    @ObservedObject var session: MonitorSession
    @EnvironmentObject var store: RayonStore
    let remove: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: RX.Space.s3) {
            HStack(spacing: RX.Space.s2) {
                RedactableText(session.machine.name, redacted: store.machineRedacted == .all)
                    .font(.rxBodyStrong)
                    .foregroundStyle(.rxInk)
                Spacer()
                RXIconButton("Remove from Menu Bar", systemImage: "xmark", kind: .plain, size: .small, action: remove)
            }
            if session.phase == .connected, session.status.hasData {
                CompactMonitorView(session: session)
            } else {
                MonitorPlaceholder(session: session)
            }
            HStack(spacing: RX.Space.s2) {
                Button {
                    dismiss()
                    openMainWindow()
                    AppRouter.shared.openTerminal(machine: session.machine.id)
                } label: {
                    Label("Terminal", systemImage: "terminal")
                }
                .buttonStyle(.rx)
                Button {
                    dismiss()
                    openMainWindow()
                    AppRouter.shared.openMonitor(machine: session.machine.id)
                } label: {
                    Label("Monitor", systemImage: "gauge.with.dots.needle.33percent")
                }
                .buttonStyle(.rx)
                Spacer()
                Button("Open Rayon") {
                    dismiss()
                    openMainWindow()
                }
                .buttonStyle(.rxPrimary)
            }
        }
        .padding(RX.Space.s4)
        .background(Color.rxWindow)
    }

    func openMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
