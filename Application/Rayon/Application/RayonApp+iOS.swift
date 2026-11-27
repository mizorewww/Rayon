//
//  RayonApp+iOS.swift
//  Rayon
//
//  Created by Lakr Aream on 2022/3/2.
//

#if os(iOS)
    import RayonModule
    import RayonTerminal
    import SwiftUI

    extension RayonApp {
        /// The UIKit answers to the dialogs RayonModule asks for.
        @MainActor static func installPlatformHandlers() {
            FileTransferInterface.uiHandler = IOSFileTransferUIHandler()
            TerminalInterface.uiHandler = IOSTerminalUIHandler()
            HostKeyTrust.handler = HostKeyTrustPrompt()
        }
    }

    /// The window: a tab bar on iPhone, a sidebar on iPad.
    struct RootView: View {
        @EnvironmentObject var store: RayonStore

        var body: some View {
            ContentView()
                .onOpenURL { url in
                    // uuremote:// external integration callbacks arrive on
                    // the app's own rayon:// scheme.
                    UULocalBridge.handleCallback(url)
                }
            #if DEBUG
                .fullScreenCover(isPresented: .constant(ProcessInfo.processInfo.environment["RAYON_PREVIEW_EDITOR"] != nil)) {
                    EditorPreviewScreen()
                }
            #endif
                .onAppear {
                    SettingsEffects.start()
                    if let problem = store.launchProblem {
                        Indicator.alert("\(problem)")
                    }
                    if let notice = store.takeMigrationNotice() {
                        Indicator.alert("Imported from the Previous Version", message: "\(notice)")
                    }
                    #if DEBUG
                        runPreviewHooks()
                    #endif
                }
                .sheet(isPresented: .constant(!store.licenseAgreed)) {
                    AgreementView()
                        .rxSolidBars()
                        .interactiveDismissDisabled()
                }
        }
    }
#endif
