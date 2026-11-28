//
//  TerminalClipboardSettings.swift
//  Rayon
//
//  Settings › Mouse & Clipboard, above Ghostty's copy settings: Rayon's own,
//  since a touch selection never passes through Ghostty's `copy-on-select`.
//

import RayonModule
import SwiftUI

struct TerminalClipboardSettings: View {
    @AppSetting(AppSettings.terminalCopiesOnSelect, title: "Copy on select") private var copiesOnSelect
    @AppSetting(AppSettings.terminalSharesClipboard, title: "Share clipboard with remote programs") private var sharesClipboard

    var body: some View {
        Toggle(isOn: $copiesOnSelect) {
            Text("Copy on select")
            Text("Copy text to the clipboard as soon as you finish selecting it.")
        }
        Toggle(isOn: $sharesClipboard) {
            Text("Share clipboard with remote programs")
            #if os(macOS)
                Text("Programs running on the server may read and write this Mac's clipboard (OSC 52), so a copy in vim or tmux lands here.")
            #else
                Text("Programs running on the server may read and write this device's clipboard (OSC 52), so a copy in vim or tmux lands here.")
            #endif
        }
    }
}
