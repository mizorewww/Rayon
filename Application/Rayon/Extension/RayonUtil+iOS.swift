//
//  RayonUtil+iOS.swift
//  Rayon
//
//  Created by Lakr Aream on 2022/3/3.
//

#if os(iOS)
    import Foundation
    import RayonModule
    import SwiftUI
    import UIKit

    let preferredPopOverSize = CGSize(width: 700, height: 555)

    @MainActor
    enum RayonUtil {
        /// Presents a SwiftUI view in a form-sheet hosting controller over the
        /// topmost view controller. Shared by all modal picker flows. When the
        /// window cannot take a modal right now — a sheet is still animating
        /// out — the present waits in PresentationQueue and `completion` hears
        /// whether it went up.
        static func presentModalSheet<Content: View>(rootView: Content, completion: ((Bool) -> Void)? = nil) {
            let controller = UIHostingController(rootView: rootView.rxSolidBars())
            controller.isModalInPresentation = true
            controller.modalTransitionStyle = .coverVertical
            controller.modalPresentationStyle = .formSheet
            controller.preferredContentSize = preferredPopOverSize
            PresentationQueue.present(controller, completion: completion)
        }

        static func selectIdentity() async -> RDIdentity.ID? {
            debugPrint("Picking Identity")
            return await withCheckedContinuation { continuation in
                let picker = NavigationStack {
                    PickIdentityView {
                        continuation.resume(returning: $0)
                    }
                }
                .expended()
                presentModalSheet(rootView: picker) { presented in
                    // No window took the picker: report no selection
                    // instead of leaking the continuation.
                    if !presented { continuation.resume(returning: nil) }
                }
            }
        }

        static func selectMachine(canSelectMany: Bool = true) async -> [RDMachine.ID] {
            debugPrint("Picking Machine")
            return await withCheckedContinuation { continuation in
                let picker = NavigationStack {
                    PickMachineView(completion: {
                        continuation.resume(returning: $0)
                    }, canSelectMany: canSelectMany)
                }
                .expended()
                presentModalSheet(rootView: picker) { presented in
                    if !presented { continuation.resume(returning: []) }
                }
            }
        }

        static func selectOneMachine() async -> [RDMachine.ID] {
            await selectMachine(canSelectMany: false)
        }

        static func createExecuteFor(snippet: RDSnippet) {
            Task {
                let machineIds = await selectMachine()
                debugPrint(machineIds)
                guard !machineIds.isEmpty else {
                    return
                }
                let runner = NavigationStack {
                    SnippetExecuteView(snippet: snippet, machines: machineIds)
                }
                .expended()
                // The picker sheet is still animating out when the
                // selection comes back; the queue waits it out.
                presentModalSheet(rootView: runner)
            }
        }
    }

#endif
