//
//  FileTransferSessionActions.swift
//  Rayon
//

import RayonModule
import SwiftUI

enum FileTransferSessionActions {
    /// Closes a server's SFTP session, and with it the editor that works
    /// over it, asking first when a transfer runs or a file is unsaved.
    @MainActor
    static func close(_ context: FileTransferContext, then: @escaping @MainActor () -> Void = {}) {
        let unsaved = EditorCenter.shared.workspaces.first { $0.id == context.id }?.hasUnsavedChanges == true
        let end = {
            FileTransferManager.shared.end(for: context.id)
            then()
        }
        if context.isProgressRunning || unsaved {
            Indicator.confirm(
                message: "Close the file transfer on \(context.machine.name)?",
                informative: unsaved
                    ? "Files open in the editor have changes that are not saved. They are lost if you close."
                    : "A transfer is still running and will be interrupted.",
                confirmTitle: unsaved ? "Discard Changes" : "Close",
                destructive: true,
                skippable: !unsaved
            ) { confirmed in
                if confirmed { MainActor.assumeIsolated { end() } }
            }
        } else {
            end()
        }
    }
}
