//
//  TitleBarDoubleClick.swift
//  Rayon
//

#if os(macOS)
    import AppKit

    /// Double-clicking a window's title bar does what System Settings ›
    /// Desktop & Dock says. The pages draw their backdrop under a toolbar
    /// without a background (`rxClearToolbar`), so a click there lands on
    /// the page's view, not on AppKit's title bar, which never sees it; the
    /// double-click is carried out here for it.
    @MainActor
    enum TitleBarDoubleClick {
        static func install() {
            NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
                guard event.clickCount == 2, let window = event.window, lands(event, onPageUnderTitleBarOf: window) else { return event }
                perform(on: window)
                return nil
            }
        }

        /// The click is in the title bar's band, on the page's own view: the
        /// title bar and the toolbar's items are not in the content view.
        private static func lands(_ event: NSEvent, onPageUnderTitleBarOf window: NSWindow) -> Bool {
            guard window.styleMask.contains(.titled), !window.styleMask.contains(.fullScreen),
                  event.locationInWindow.y >= window.contentLayoutRect.maxY,
                  let content = window.contentView, let frame = content.superview,
                  let hit = frame.hitTest(event.locationInWindow)
            else { return false }
            return hit.isDescendant(of: content) && !(hit is NSControl) && !(hit is NSText)
        }

        private static func perform(on window: NSWindow) {
            switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
            case "Minimize":
                window.performMiniaturize(nil)
            case "None":
                break
            case "Fill":
                if let screen = window.screen { window.setFrame(screen.visibleFrame, display: true, animate: true) }
            default:
                // "Maximize", and the default.
                window.performZoom(nil)
            }
        }
    }
#endif
