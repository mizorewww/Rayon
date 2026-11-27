//
//  MoreMenu+macOS.swift
//  Rayon
//

#if os(macOS)
    import SwiftUI

    extension View {
        /// The ⋯ menu at the end of a row or card: the icon alone, borderless.
        func moreMenu() -> some View {
            labelStyle(.iconOnly)
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
        }
    }
#endif
