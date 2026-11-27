//
//  RayonApp.swift
//  Rayon
//
//  The app's entry on every platform. What each platform installs at launch,
//  its window's root view and the Mac's app delegate are in RayonApp+macOS
//  and RayonApp+iOS.
//

import RayonModule
import SwiftUI

@main
struct RayonApp: App {
    @StateObject private var store = RayonStore.shared
    #if os(macOS)
        @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    init() {
        #if DEBUG
            Logger.app.debugFile("command arguments: \(CommandLine.arguments.joined(separator: " "))")
        #endif
        Self.installPlatformHandlers()
        _ = RayonStore.shared
        CloudSyncModel.shared.start()
        Logger.app.infoFile("launched")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
        #if os(macOS)
        .windowToolbarStyle(.unified)
        #endif
        .commands {
            SidebarCommands()
            #if os(macOS)
                RayonCommands()
            #endif
        }
    }
}
