//
//  Pasteboard.swift
//  Rayon
//

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

@MainActor
enum Pasteboard {
    /// Copies the text; on iOS a toast says so, since nothing else shows it.
    static func copy(_ string: String) {
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        #else
            UIPasteboard.general.string = string
            Indicator.success("Copied")
        #endif
    }
}
