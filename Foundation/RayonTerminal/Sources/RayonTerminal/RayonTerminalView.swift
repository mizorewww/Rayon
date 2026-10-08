import AppKit
import GhosttyTerminal
import SwiftUI

/// One native terminal per SSH context. Copies of this SwiftUI value share the
/// same view/session, preserving scrollback when a terminal moves between windows.
public struct RayonTerminalView: NSViewRepresentable {
    nonisolated let session: RayonTerminalSession

    nonisolated public init() { session = RayonTerminalSession() }

    public func makeNSView(context: Context) -> AppTerminalView { session.platformView() }
    public func updateNSView(_ view: AppTerminalView, context: Context) {}

    nonisolated public func write(_ string: String) { session.output.write(Data(string.utf8)) }

    nonisolated public func setTerminalFontSize(with size: Int) {
        session.callbacks.setFontSize(size)
        let session = session
        DispatchQueue.main.async { session.applyFontSize() }
    }

    nonisolated public func requestTerminalSize() -> CGSize { session.callbacks.terminalSize }

    @discardableResult
    nonisolated public func setupBufferChain(callback: ((String) -> Void)?) -> Self {
        session.callbacks.setInput(callback)
        return self
    }

    @discardableResult
    nonisolated public func setupTitleChain(callback: ((String) -> Void)?) -> Self {
        session.callbacks.setTitle(callback)
        return self
    }

    @discardableResult
    nonisolated public func setupBellChain(callback: (() -> Void)?) -> Self {
        session.callbacks.setBell(callback)
        return self
    }

    @discardableResult
    nonisolated public func setupSizeChain(callback: ((CGSize) -> Void)?) -> Self {
        session.callbacks.setResize(callback)
        return self
    }
}

/// Only the immutable/thread-safe transport objects cross queues. AppKit storage
/// and all Ghostty view operations are explicitly main-actor isolated.
final class RayonTerminalSession: @unchecked Sendable {
    let callbacks: TerminalCallbacks
    let backend: InMemoryTerminalSession
    let output: TerminalOutputBuffer
    @MainActor private var presentation: TerminalPresentation?

    init() {
        let callbacks = TerminalCallbacks()
        self.callbacks = callbacks
        let backend = InMemoryTerminalSession(
            write: { callbacks.receiveInput($0) },
            resize: { callbacks.receiveSize(columns: Int($0.columns), rows: Int($0.rows)) }
        )
        self.backend = backend
        output = TerminalOutputBuffer { backend.receive($0) }
    }

    @MainActor func platformView() -> AppTerminalView {
        if let presentation { return presentation.view }
        let presentation = TerminalPresentation(session: self)
        self.presentation = presentation
        return presentation.view
    }

    @MainActor func applyFontSize() { presentation?.applyFontSize() }
}

@MainActor
private final class TerminalPresentation: TerminalSurfaceTitleDelegate,
    TerminalSurfaceBellDelegate, TerminalSurfaceLifecycleDelegate,
    TerminalSurfaceClipboardConfirmationDelegate
{
    private static let controller = TerminalController(
        configuration: TerminalConfiguration.default
            .custom("clipboard-read", "ask")
            .custom("clipboard-write", "ask")
    )
    let view: AppTerminalView
    private let callbacks: TerminalCallbacks
    private let output: TerminalOutputBuffer

    // SSH workers may release the last session reference. Ghostty's coordinator
    // requires main-actor teardown, including destruction of this view's fields.
    isolated deinit {}

    init(session: RayonTerminalSession) {
        callbacks = session.callbacks
        output = session.output
        view = AppTerminalView(frame: .zero)
        view.delegate = self
        view.controller = Self.controller
        // Never use the default .exec backend: SSH remains owned by Rayon.
        view.configuration = TerminalSurfaceOptions(
            backend: .inMemory(session.backend), fontSize: Float(callbacks.fontSize)
        )
    }

    func applyFontSize() {
        // Changing configuration.fontSize would recreate the surface and erase
        // scrollback. A binding action updates the existing surface in place.
        _ = view.performBindingAction("set_font_size:\(callbacks.fontSize)")
    }

    func terminalDidAttachSurface(_ surface: TerminalSurface) {
        applyFontSize()
        output.setAttached(true)
    }

    func terminalDidDetachSurface() { output.setAttached(false) }
    func terminalDidChangeTitle(_ title: String) { callbacks.receiveTitle(title) }
    func terminalDidRingBell() { callbacks.receiveBell() }

    func terminalDidRequestClipboardConfirmation(_ request: TerminalClipboardConfirmationRequest) {
        // Preserve user-initiated paste, without granting a remote program
        // implicit permission to read or replace the system clipboard.
        request.respond(allow: request.kind == .paste)
    }
}
