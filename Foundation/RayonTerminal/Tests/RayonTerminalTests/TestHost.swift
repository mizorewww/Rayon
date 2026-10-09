import GhosttyTerminal
import XCTest
@testable import RayonTerminal

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// A real window holding a terminal view, so the Ghostty surface attaches the
/// same way it does in the app: an NSWindow on macOS, a UIWindow on iOS.
@MainActor
final class TestHost {
    #if os(macOS)
        private let window: NSWindow
    #else
        private let window: UIWindow
    #endif

    static func prepare() {
        #if os(macOS)
            _ = NSApplication.shared
        #endif
    }

    init(_ view: PlatformTerminalView? = nil, size: CGSize = CGSize(width: 640, height: 400)) {
        Self.prepare()
        #if os(macOS)
            window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .resizable], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = view
            window.orderFront(nil)
        #else
            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
            window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
            window.frame = CGRect(origin: .zero, size: size)
            let controller = UIViewController()
            if let view {
                view.frame = controller.view.bounds
                view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                controller.view.addSubview(view)
            }
            window.rootViewController = controller
            window.isHidden = false
        #endif
    }

    func show(_ view: PlatformTerminalView) {
        #if os(macOS)
            window.contentView = view
        #else
            view.frame = window.rootViewController?.view.bounds ?? window.bounds
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            window.rootViewController?.view.addSubview(view)
        #endif
    }

    func resize(_ size: CGSize) {
        #if os(macOS)
            window.setContentSize(size)
        #else
            window.frame = CGRect(origin: .zero, size: size)
            window.layoutIfNeeded()
        #endif
    }

    /// Detaches the content and closes the window.
    func close() {
        #if os(macOS)
            window.contentView = nil
            window.close()
        #else
            window.rootViewController?.view.subviews.forEach { $0.removeFromSuperview() }
            window.isHidden = true
            window.rootViewController = nil
        #endif
    }
}

/// The general pasteboard's plain text, read and written the same way on both
/// platforms, plus a full snapshot so a test leaves the user's clipboard as it was.
@MainActor
enum TestPasteboard {
    #if os(macOS)
        typealias Snapshot = [NSPasteboardItem]
    #else
        typealias Snapshot = [[String: Any]]
    #endif

    /// Every readable representation, not just text. On iOS this is empty:
    /// reading another app's pasteboard raises the "Allow Paste" prompt, which
    /// nobody can answer in a test run, and the simulator's pasteboard is not
    /// the user's anyway.
    static func save() -> Snapshot {
        #if os(macOS)
            (NSPasteboard.general.pasteboardItems ?? []).map { item in
                let copy = NSPasteboardItem()
                for type in item.types {
                    if let data = item.data(forType: type) { copy.setData(data, forType: type) }
                }
                return copy
            }
        #else
            []
        #endif
    }

    static func restore(_ snapshot: Snapshot) {
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(snapshot)
        #else
            UIPasteboard.general.items = []
        #endif
    }

    static var string: String? {
        get {
            #if os(macOS)
                NSPasteboard.general.string(forType: .string)
            #else
                UIPasteboard.general.string
            #endif
        }
        set {
            #if os(macOS)
                NSPasteboard.general.clearContents()
                if let newValue { NSPasteboard.general.setString(newValue, forType: .string) }
            #else
                UIPasteboard.general.string = newValue
            #endif
        }
    }
}
