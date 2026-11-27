//
//  SettingsEffects.swift
//  Rayon
//
//  The settings that act outside SwiftUI views: applied at launch and on
//  every change, whether made in Settings, by another device through iCloud
//  or by a restored backup.
//

import Combine
import RayonModule
import RayonTerminal

@MainActor
enum SettingsEffects {
    private static var subscriptions: Set<AnyCancellable> = []

    static func start() {
        guard subscriptions.isEmpty else { return }
        // 2.8's settings, before the first is applied.
        LegacySettingsImport.run()
        // At once, so the first window does not show the other appearance.
        AppSettings.appearance.value.apply()
        AppSettings.appearance.publisher
            .sink { appearance in MainActor.assumeIsolated { appearance.apply() } }
            .store(in: &subscriptions)
        AppSettings.terminalCopiesOnSelect.publisher
            .sink { enabled in MainActor.assumeIsolated { RayonTerminalView.setCopyOnSelect(enabled) } }
            .store(in: &subscriptions)
        AppSettings.terminalSharesClipboard.publisher
            .sink { enabled in MainActor.assumeIsolated { RayonTerminalView.setClipboardSharing(enabled) } }
            .store(in: &subscriptions)
        // One font size: the terminal's Size setting also sets the size
        // sessions start from and ⌘+ and ⌘− change.
        TerminalSettings.shared.onFontSizeChange = { size in
            AppSettings.terminalFontSize.set(Int(size.rounded()))
        }
    }
}
