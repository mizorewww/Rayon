//
//  RayonApp.swift
//  Shared
//
//  Created by Lakr Aream on 2022/2/8.
//

import AppKit
import CodeEditorUI
import RayonModule
import RayonTerminal
import SwiftUI

@main
struct RayonApp: App {
    @StateObject private var store = RayonStore.shared

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        #if DEBUG
            NSLog(CommandLine.arguments.joined(separator: "\n"))
        #endif
        _ = RayonStore.shared

        // Shared file-transfer core lives in RayonModule; register the
        // platform UI handler it delegates to.
        FileTransferInterface.uiHandler = MacFileTransferUIHandler()

        NSLog("static main completed")
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(store)
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            SidebarCommands()
            RayonCommands()
        }
    }
}

/// Menu commands: New Server, Settings (Settings is a sidebar destination), navigation.
struct RayonCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { AppRouter.shared.openSettings() }
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(after: .newItem) {
            Button("New Server…") { AppRouter.shared.presentNewServer = true }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Batch Startup…") { AppRouter.shared.batchStartup() }
        }
        CommandGroup(after: .sidebar) {
            Button("Home") { AppRouter.shared.route = .home }
                .keyboardShortcut("1", modifiers: .command)
            Button("Servers") { AppRouter.shared.route = .servers }
                .keyboardShortcut("2", modifiers: .command)
            Button("Identities") { AppRouter.shared.route = .identities }
                .keyboardShortcut("3", modifiers: .command)
            Button("Snippets") { AppRouter.shared.route = .snippets }
                .keyboardShortcut("4", modifiers: .command)
            Button("Port Forward") { AppRouter.shared.route = .portForward }
                .keyboardShortcut("5", modifiers: .command)
            Divider()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    nonisolated(unsafe) private(set) static var shared: AppDelegate!

    override init() {
        super.init()
        debugPrint("\(self) \(#function)")
        assert(AppDelegate.shared == nil, "duplicated init of AppDelegate")
        AppDelegate.shared = self

        let timer = Timer(
            timeInterval: 1,
            target: self,
            selector: #selector(windowStatusWatcher),
            userInfo: nil,
            repeats: true
        )
        CFRunLoopAddTimer(CFRunLoopGetMain(), timer, .commonModes)
    }

    func applicationDidFinishLaunching(_: Notification) {
        AppearancePreference.applyStored()
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        if !TerminalManager.shared.sessionContexts.isEmpty {
            UIBridge.requiresConfirmation(
                message: "Quit Rayon?",
                informative: "Open terminal sessions will be closed.",
                confirmTitle: "Quit",
                destructive: true
            ) { confirmed in
                guard confirmed else { return }
                TerminalManager.shared.closeAll()
                NSApp.terminate(nil)
            }
            return .terminateCancel
        }
        return .terminateNow
    }

    @objc
    func windowStatusWatcher() {
        let windows = NSApp.windows
            .filter { window in
                guard let readClass = NSClassFromString("NSStatusBarWindow") else {
                    return true
                }
                return !window.isKind(of: readClass.self)
            }
            .filter { $0.isVisible }
        if windows.isEmpty, MenubarTool.shared.hasCat {
            NSApp.setActivationPolicy(.accessory)
        } else {
            NSApp.setActivationPolicy(.regular)
        }
    }
}
