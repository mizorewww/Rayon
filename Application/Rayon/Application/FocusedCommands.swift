//
//  FocusedCommands.swift
//  Rayon
//
//  What the menu-bar commands act on. The page in front publishes its
//  actions with focusedSceneValue and RayonCommands reads them, so a
//  shortcut works on the Mac's menu bar and on an iPad's hardware keyboard
//  alike, and only for the page on screen.
//

import SwiftUI

/// The terminal in front. A nil action is one the page cannot do now.
struct TerminalCommandActions {
    var find: () -> Void
    var splitRight: (() -> Void)?
    var splitDown: (() -> Void)?
    var splitWithServer: (() -> Void)?
    /// The tabs of the server (or command) in front.
    var tabCount: Int
    /// Shows the tab at this index.
    var selectTab: (Int) -> Void
    /// Shows the tab this many places along, wrapping around.
    var cycleTab: (Int) -> Void
    /// On the Mac, New Terminal and Close Tab act on whatever is in front;
    /// on iOS, the terminal page does.
    var newTab: (() -> Void)?
    var closeTab: (() -> Void)?
}

/// The editor in front.
struct EditorCommandActions {
    var save: (() -> Void)?
    var openFile: () -> Void
    var closeFile: (() -> Void)?
}

/// The file browser in front.
struct FileBrowserCommandActions {
    var back: (() -> Void)?
    var forward: (() -> Void)?
    var enclosingFolder: (() -> Void)?
    var goToFolder: (() -> Void)?
    var reload: (() -> Void)?
}

extension FocusedValues {
    @Entry var terminalCommands: TerminalCommandActions?
    @Entry var editorCommands: EditorCommandActions?
    @Entry var fileBrowserCommands: FileBrowserCommandActions?
    /// Deletes what is selected in the list in front, asking first.
    @Entry var deleteSelection: (() -> Void)?
}
