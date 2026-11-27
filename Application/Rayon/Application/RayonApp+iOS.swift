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
            HostKeyTrust.handler = IOSHostKeyTrustHandler()
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
                    AppearancePreference.applyStored()
                    RayonTerminalView.setCopyOnSelect(store.terminalCopyOnSelect)
                    RayonTerminalView.setClipboardSharing(store.terminalClipboardSharing)
                    checkAgreement()
                    if let problem = store.launchProblem {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { UIBridge.presentAlert(with: problem) }
                    }
                    #if DEBUG
                        runPreviewHooks()
                    #endif
                }
                .onChange(of: store.licenseAgreed) { _ in
                    checkAgreement()
                }
        }

        func checkAgreement() {
            guard !store.licenseAgreed else {
                return
            }
            let host = UIHostingController(rootView: AgreementView().rxSolidBars())
            host.preferredContentSize = preferredPopOverSize
            host.isModalInPresentation = true
            host.modalTransitionStyle = .coverVertical
            host.modalPresentationStyle = .formSheet
            // At launch the window is not in the hierarchy yet; the queue
            // replays the present once it is.
            PresentationQueue.present(next: host)
        }
    }
#endif
