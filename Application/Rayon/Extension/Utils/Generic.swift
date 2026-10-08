//
//  Generic.swift
//  Rayon
//
//  Created by Lakr Aream on 2022/2/11.
//

import Foundation
import RayonModule
import SwiftUI

enum RayonUtil {
    static func findWindow() -> NSWindow? {
        if let key = NSApp.keyWindow {
            return key
        }
        for window in NSApp.windows where window.isVisible {
            return window
        }
        return nil
    }
}

/// Presents SwiftUI content as a sheet on the frontmost window from code that
/// has no view to hang a `.sheet` on (router actions, menu bar).
enum SheetPresenter {
    @MainActor
    static func present<Content: View>(
        size: CGSize? = nil,
        @ViewBuilder content: @escaping (_ dismiss: @escaping () -> Void) -> Content
    ) {
        var panelRef: NSPanel?
        var windowRef: NSWindow?
        let dismiss = {
            guard let panel = panelRef else { return }
            if let window = windowRef {
                window.endSheet(panel)
            } else {
                panel.close()
            }
            panelRef = nil
        }
        let root = content(dismiss)
            .environmentObject(RayonStore.shared)
            .frame(width: size?.width, height: size?.height)
        let controller = NSHostingController(rootView: root)
        let panel = NSPanel(contentViewController: controller)
        panel.title = ""
        panel.titleVisibility = .hidden
        panelRef = panel
        if let window = RayonUtil.findWindow() {
            windowRef = window
            window.beginSheet(panel) { _ in }
        } else {
            panel.center()
            panel.makeKeyAndOrderFront(nil)
        }
    }
}

enum ServerPickerPanel {
    /// The multi-select server picker used by Batch Startup, Run snippet and Port Forward.
    @MainActor
    static func present(
        title: String,
        lead: String? = nil,
        confirmTitle: String,
        allowsMany: Bool,
        preselected: Set<RDMachine.ID> = [],
        onComplete: @escaping ([RDMachine.ID]) -> Void
    ) {
        SheetPresenter.present { dismiss in
            ServerPickerSheet(
                title: title,
                lead: lead,
                confirmTitle: confirmTitle,
                allowsMany: allowsMany,
                initialSelection: preselected
            ) { selection in
                dismiss()
                guard let selection, !selection.isEmpty else { return }
                onComplete(selection)
            }
        }
    }
}

enum IdentityPickerPanel {
    @MainActor
    static func present(onComplete: @escaping (RDIdentity.ID?) -> Void) {
        SheetPresenter.present { dismiss in
            IdentityPickerSheet { selection in
                dismiss()
                onComplete(selection)
            }
        }
    }
}
