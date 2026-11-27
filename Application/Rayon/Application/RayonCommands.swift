//
//  RayonCommands.swift
//  Rayon
//
//  The menu-bar commands, on the Mac and on iPad (whose hardware keyboard
//  lists them when ⌘ is held). Terminal, Editor and Go act on the page in
//  front through FocusedCommands; the Mac's app and window commands are in
//  RayonCommands+macOS.
//

import RayonModule
import SwiftUI

struct RayonCommands: Commands {
    @FocusedValue(\.terminalCommands) private var terminal
    @FocusedValue(\.editorCommands) private var editor
    @FocusedValue(\.fileBrowserCommands) private var files
    @FocusedValue(\.deleteSelection) private var deleteSelection
    @ObservedObject private var store = RayonStore.shared

    var body: some Commands {
        #if os(macOS)
            MacAppCommands(terminalInFront: terminal != nil)
        #endif
        CommandGroup(after: .newItem) {
            #if os(iOS)
                Button("New Terminal Tab", action: run(terminal?.newTab))
                    .keyboardShortcut("t", modifiers: .command)
                    .disabled(terminal?.newTab == nil)
            #endif
            Button("Open File…", action: run(editor?.openFile))
                .keyboardShortcut("o", modifiers: .command)
                .disabled(editor == nil)
        }
        CommandGroup(after: .saveItem) {
            Button("Save", action: run(editor?.save))
                .keyboardShortcut("s", modifiers: .command)
                .disabled(editor?.save == nil)
            #if os(iOS)
                // The Mac's ⌘W closes the session page in front instead.
                if terminal != nil {
                    Button("Close Tab", action: run(terminal?.closeTab))
                        .keyboardShortcut("w", modifiers: .command)
                        .disabled(terminal?.closeTab == nil)
                } else {
                    Button("Close File", action: run(editor?.closeFile))
                        .keyboardShortcut("w", modifiers: .command)
                        .disabled(editor?.closeFile == nil)
                }
            #else
                Button("Close File", action: run(editor?.closeFile))
                    .disabled(editor?.closeFile == nil)
            #endif
        }
        CommandGroup(after: .pasteboard) {
            Button("Delete…", action: run(deleteSelection))
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(deleteSelection == nil)
        }
        CommandMenu("Terminal") {
            Button("Find in Terminal", action: run(terminal?.find))
                .keyboardShortcut("f", modifiers: .command)
                .disabled(terminal == nil)
            Divider()
            Button("Split Right", action: run(terminal?.splitRight))
                .keyboardShortcut("d", modifiers: .command)
                .disabled(terminal?.splitRight == nil)
            Button("Split Down", action: run(terminal?.splitDown))
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(terminal?.splitDown == nil)
            #if os(macOS)
                Button("Split with Server…", action: run(terminal?.splitWithServer))
                    .keyboardShortcut("d", modifiers: [.command, .option])
                    .disabled(terminal?.splitWithServer == nil)
            #endif
            Divider()
            Button("Smaller Text") { store.terminalFontSize -= 1 }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(terminal == nil || store.terminalFontSize <= 4)
            Button("Larger Text") { store.terminalFontSize += 1 }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(terminal == nil || store.terminalFontSize >= 30)
            Divider()
            Button("Previous Tab") { terminal?.cycleTab(-1) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled((terminal?.tabCount ?? 0) < 2)
            Button("Next Tab") { terminal?.cycleTab(1) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled((terminal?.tabCount ?? 0) < 2)
            if let terminal, terminal.tabCount > 0 {
                Divider()
                // ⌘1…⌘8 pick that tab, ⌘9 the last.
                ForEach(0 ..< min(terminal.tabCount, 8), id: \.self) { index in
                    Button("Tab \(index + 1)") { terminal.selectTab(index) }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
                Button("Last Tab") { terminal.selectTab(terminal.tabCount - 1) }
                    .keyboardShortcut("9", modifiers: .command)
            }
        }
        CommandMenu("Go") {
            Button("Back", action: run(files?.back))
                .keyboardShortcut("[", modifiers: .command)
                .disabled(files?.back == nil)
            Button("Forward", action: run(files?.forward))
                .keyboardShortcut("]", modifiers: .command)
                .disabled(files?.forward == nil)
            Button("Enclosing Folder", action: run(files?.enclosingFolder))
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(files?.enclosingFolder == nil)
            Button("Go to Folder…", action: run(files?.goToFolder))
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(files?.goToFolder == nil)
            Divider()
            Button("Reload", action: run(files?.reload))
                .keyboardShortcut("r", modifiers: .command)
                .disabled(files?.reload == nil)
        }
    }

    /// A page's action, held back while the Mac shows a sheet or a modal
    /// over the window: the menu bar stays live under one.
    private func run(_ action: (() -> Void)?) -> () -> Void {
        {
            #if os(macOS)
                if RayonUtil.isShowingSheetOrModal { return }
            #endif
            action?()
        }
    }
}
