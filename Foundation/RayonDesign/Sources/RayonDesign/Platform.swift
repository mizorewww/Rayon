//
//  Platform.swift
//  RayonDesign
//
//  Control styles that exist on one platform only, expressed once so views can
//  stay shared between macOS and iOS.
//

import SwiftUI

public extension View {
    /// A checkbox on macOS; iOS has no checkbox, so a switch there.
    func rxCheckboxToggle() -> some View {
        #if os(macOS)
            toggleStyle(.checkbox)
        #else
            toggleStyle(.switch)
        #endif
    }

    /// A menu drawn as a button (macOS needs the button menu style; on iOS a
    /// `Menu` already is one), optionally without the disclosure indicator.
    func rxButtonMenu(indicator: Bool = true) -> some View {
        #if os(macOS)
            menuStyle(.button).menuIndicator(indicator ? .automatic : .hidden)
        #else
            menuIndicator(indicator ? .automatic : .hidden)
        #endif
    }

    /// An inline text link: the link button style on macOS, a borderless
    /// button on iOS.
    func rxLinkButton() -> some View {
        #if os(macOS)
            buttonStyle(.link)
        #else
            buttonStyle(.borderless)
        #endif
    }
}
