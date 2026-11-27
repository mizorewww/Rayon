//
//  TerminalSessionActions.swift
//  Rayon
//

import RayonModule

/// Closing terminal tabs. A live session asks first, except on a UU Remote
/// device, whose session outlives its tab and can be resumed. Where the
/// window goes next differs by platform: see the +macOS and +iOS extensions.
enum TerminalSessionActions {
    @MainActor
    static func confirmClose(
        _ context: TerminalManager.Context,
        informative: LocalizedStringResource? = nil,
        then perform: @escaping @MainActor () -> Void
    ) {
        let manager = TerminalManager.shared
        guard manager.sessionAlive(forContext: context.id), !context.machine.isUURemoteDevice else {
            return perform()
        }
        Indicator.confirm(
            message: "Close this terminal tab?",
            informative: informative ?? "Its session on \(context.displayName) ends.",
            confirmTitle: "Close Tab",
            destructive: true,
            skippable: true
        ) { confirmed in
            if confirmed { MainActor.assumeIsolated { perform() } }
        }
    }
}
