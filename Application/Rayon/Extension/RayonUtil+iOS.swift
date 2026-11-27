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
        /// Presents a SwiftUI view as a form sheet over the topmost view
        /// controller, for the pickers that actions outside any view ask for.
        static func presentModalSheet<Content: View>(rootView: Content) {
            let controller = UIHostingController(rootView: rootView.rxSolidBars())
            controller.isModalInPresentation = true
            controller.modalTransitionStyle = .coverVertical
            controller.modalPresentationStyle = .formSheet
            controller.preferredContentSize = preferredPopOverSize
            ModalPresenter.present(controller)
        }

        static func selectMachine(canSelectMany: Bool = true) async -> [RDMachine.ID] {
            await withCheckedContinuation { continuation in
                let picker = NavigationStack {
                    PickMachineView(completion: {
                        continuation.resume(returning: $0)
                    }, canSelectMany: canSelectMany)
                }
                .expended()
                presentModalSheet(rootView: picker)
            }
        }

        static func selectOneMachine() async -> [RDMachine.ID] {
            await selectMachine(canSelectMany: false)
        }

        static func createExecuteFor(snippet: RDSnippet) {
            Task {
                let machineIds = await selectMachine()
                guard !machineIds.isEmpty else {
                    return
                }
                let runner = NavigationStack {
                    SnippetExecuteView(snippet: snippet, machines: machineIds)
                }
                .expended()
                // The picker sheet is still animating out when the
                // selection comes back; the present follows it.
                presentModalSheet(rootView: runner)
            }
        }
    }

#endif
