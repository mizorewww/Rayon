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

        static func createExecuteFor(snippet: RDSnippet) {
            ServerPicker.present(title: "Run \(snippet.name)", lead: "Servers need an identity set.", confirmTitle: "Run") { machines in
                // The picker sheet is still animating out when the
                // selection comes back; the present follows it.
                presentModalSheet(rootView: NavigationStack {
                    SnippetExecuteView(snippet: snippet, machines: machines)
                }
                .expended())
            }
        }
    }

#endif
