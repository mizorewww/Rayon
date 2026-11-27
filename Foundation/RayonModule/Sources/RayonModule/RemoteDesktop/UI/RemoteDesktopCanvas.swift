//
//  RemoteDesktopCanvas.swift
//  RayonModule
//
//  The interactive remote-desktop canvas shared by both apps. Draws the
//  session's frames aspect-fit, overlays the remote cursor when the host
//  draws its own pointer, and turns pointer, wheel and keyboard events
//  into `RemoteDesktopSession` input calls. UIKit and AppKit backends
//  share the same public surface so the SwiftUI stage view stays one
//  implementation.
//

import SwiftUI

#if canImport(UIKit)
import UIKit

/// SwiftUI shell around `RemoteDesktopCanvasView`; the control chrome
/// lives in `RemoteDesktopStageView` above it.
public struct RemoteDesktopCanvas: UIViewRepresentable {
    @ObservedObject public var session: RemoteDesktopSession
    /// Bumped to toggle the software keyboard on platforms that have one.
    public var keyboardRequests: Int
    /// How fingers drive the pointer on a touch screen.
    public var touchMode: RemoteDesktopTouchMode

    public init(session: RemoteDesktopSession, keyboardRequests: Int = 0, touchMode: RemoteDesktopTouchMode = .trackpad) {
        self.session = session
        self.keyboardRequests = keyboardRequests
        self.touchMode = touchMode
    }

    public func makeUIView(context _: Context) -> RemoteDesktopCanvasView {
        let view = RemoteDesktopCanvasView()
        view.session = session
        view.touchMode = touchMode
        // A canvas made again (the page came back) does not bring up the
        // keyboard for requests an earlier one already answered.
        view.syncKeyboardRequests(keyboardRequests)
        view.follow(session)
        return view
    }

    public static func dismantleUIView(_ view: RemoteDesktopCanvasView, coordinator _: ()) {
        view.session?.stopObservingFrames(by: view)
    }

    public func updateUIView(_ view: RemoteDesktopCanvasView, context _: Context) {
        view.touchMode = touchMode
        if view.session !== session { view.follow(session) }
        view.applyKeyboardRequest(keyboardRequests)
    }
}

/// Draws the remote framebuffer and captures local input. iPadOS
/// trackpads/mice and Mac Catalyst report through `UIHoverGestureRecognizer`
/// and the press recognizers, wheel/trackpad scrolls through
/// `UIPanGestureRecognizer` scroll types, and hardware keys through
/// `presses*`; all of them point where they are. On a touch screen, fingers
/// go through `RemoteDesktopTouchGestures` (a trackpad by default, or
/// direct touch), and the software keyboard comes up only when asked for.
public final class RemoteDesktopCanvasView: UIView {
    /// The session receiving input; set by the representable.
    public var session: RemoteDesktopSession?
    /// How fingers drive the pointer; a gesture under way is let go of when
    /// it changes.
    public var touchMode: RemoteDesktopTouchMode = .trackpad {
        didSet {
            guard touchMode != oldValue else { return }
            perform(gestures.cancelled())
            gestures.mode = touchMode
        }
    }

    /// Fingers work as on Moonlight on an iPad or iPhone; Mac Catalyst has
    /// no touch screen and keeps its pointer model.
    #if os(iOS) && !targetEnvironment(macCatalyst)
        static let usesTouchGestures = true
    #else
        static let usesTouchGestures = false
    #endif

    /// Shows the pictures: each IOSurface goes on screen as it is.
    private let frameView = RemoteDesktopFrameView()
    private let cursorView = UIImageView()
    /// The pointer drawn here on a touch screen when the host draws none:
    /// a finger moving it like a trackpad must see where it is.
    private let localPointerView = UIImageView(image: RemoteDesktopCanvasView.arrow)
    private var framebufferSize: CGSize = .zero
    private var cursorPosition = CGPoint.zero
    private var cursorPixelSize = CGSize.zero
    private var appliedKeyboardRequests = 0
    private var scrollAccumX: CGFloat = 0
    private var scrollAccumY: CGFloat = 0
    /// Where the pointer is, normalized: where a pencil, mouse or finger put
    /// it, and where a trackpad finger moves it from.
    private var lastNormalized = CGPoint(x: 0.5, y: 0.5) {
        didSet { if Self.usesTouchGestures, lastNormalized != oldValue { setNeedsLayout() } }
    }
    private var primaryPress: UILongPressGestureRecognizer!
    private var secondaryPress: UITapGestureRecognizer!
    private var tertiaryPress: UITapGestureRecognizer!
    private var gestures = RemoteDesktopTouchGestures()
    /// The picture's pinch zoom.
    private var viewport = RemoteDesktopViewport()
    /// The text input the software keyboard comes up for, and the input
    /// methods compose in. The canvas takes hardware keys itself and is no
    /// text input, so focusing it never shows a keyboard.
    private let keyboardProxy = RemoteDesktopKeyboardProxy()
    /// The held hardware key being repeated.
    private var keyRepeat: (press: UIPress, task: Task<Void, Never>)?
    /// Hardware keys down now, by HID usage.
    private var heldUsages: Set<Int> = []
    /// Keys a press or a key command sent this run-loop turn (whichever
    /// came first claims the key), and the presses that came after their
    /// command.
    private var keysFromPresses: Set<Int> = []
    private var keysFromCommands: Set<Int> = []
    private var pressesFromCommands: Set<UIPress> = []
    #if os(iOS) && !targetEnvironment(macCatalyst)
        private var pointerInteraction: UIPointerInteraction?
        private let dragFeedback = UIImpactFeedbackGenerator(style: .light)
    #endif

    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func commonInit() {
        backgroundColor = .black
        isUserInteractionEnabled = true
        isMultipleTouchEnabled = Self.usesTouchGestures
        cursorView.isUserInteractionEnabled = false
        cursorView.isHidden = true
        localPointerView.isUserInteractionEnabled = false
        localPointerView.isHidden = true
        addSubview(frameView)
        addSubview(cursorView)
        addSubview(localPointerView)
        keyboardProxy.canvas = self
        keyboardProxy.inputAccessoryView = keyboardAccessory
        keyboardProxy.isUserInteractionEnabled = false
        addSubview(keyboardProxy)

        let hover = UIHoverGestureRecognizer(target: self, action: #selector(hoverMoved(_:)))
        addGestureRecognizer(hover)

        // A zero-duration long press gives real down/drag/up for the
        // primary button on both touch and indirect-pointer input.
        primaryPress = UILongPressGestureRecognizer(target: self, action: #selector(pressRecognized(_:)))
        primaryPress.minimumPressDuration = 0
        primaryPress.allowableMovement = .greatestFiniteMagnitude
        if Self.usesTouchGestures {
            // Fingers are the touch handlers'; a pencil and a mouse or
            // trackpad button press where they are.
            primaryPress.allowedTouchTypes = [
                NSNumber(value: UITouch.TouchType.indirectPointer.rawValue),
                NSNumber(value: UITouch.TouchType.pencil.rawValue),
            ]
        }
        addGestureRecognizer(primaryPress)

        // `buttonMaskRequired` only exists on UITapGestureRecognizer, so
        // right/middle buttons are sent as clicks; secondary-button drags
        // are not reachable through UIKit on Catalyst.
        secondaryPress = UITapGestureRecognizer(target: self, action: #selector(clickRecognized(_:)))
        secondaryPress.buttonMaskRequired = .secondary
        addGestureRecognizer(secondaryPress)

        tertiaryPress = UITapGestureRecognizer(target: self, action: #selector(clickRecognized(_:)))
        // UIEventButtonMask tops out at .secondary; button 3 is the middle click.
        tertiaryPress.buttonMaskRequired = .button(3)
        addGestureRecognizer(tertiaryPress)

        // Scroll wheels and trackpad scrolls arrive as zero-touch pans on
        // both iPadOS and Mac Catalyst.
        let scroll = UIPanGestureRecognizer(target: self, action: #selector(scrollPanned(_:)))
        scroll.allowedScrollTypesMask = [.discrete, .continuous]
        scroll.minimumNumberOfTouches = 0
        scroll.maximumNumberOfTouches = 0
        addGestureRecognizer(scroll)

        #if os(iOS) && !targetEnvironment(macCatalyst)
            let pointer = UIPointerInteraction(delegate: self)
            addInteraction(pointer)
            pointerInteraction = pointer
        #endif
    }

    // MARK: - Frames

    /// Draws `session`'s frames and cursor as they come, straight from it:
    /// SwiftUI is not asked to draw anything for a frame.
    func follow(_ session: RemoteDesktopSession) {
        if let previous = self.session, previous !== session { previous.stopObservingFrames(by: self) }
        self.session = session
        session.observeFrames(
            by: self,
            frame: { [weak self] picture, size in self?.applyFrame(picture, framebufferSize: size) },
            cursor: { [weak self] cursor in self?.applyCursor(cursor) }
        )
        applyFrame(session.framePicture, framebufferSize: session.framebufferSize)
        applyCursor(session.remoteCursor)
    }

    func applyFrame(_ picture: RemoteDesktopPicture?, framebufferSize: CGSize) {
        let first = frameView.picture == nil
        if let picture { frameView.show(picture) }
        // A frame of the same size draws where the last one was; the first
        // picture brings up the local pointer.
        guard framebufferSize != self.framebufferSize || frameView.frame.isEmpty || (first && picture != nil) else { return }
        self.framebufferSize = framebufferSize
        setNeedsLayout()
    }

    func applyCursor(_ cursor: RemoteCursorInfo?) {
        let wasHidden = cursorView.isHidden
        if let cursor, cursor.visible, let image = cursor.image {
            cursorView.image = UIImage(cgImage: image)
            cursorView.isHidden = false
            cursorPosition = CGPoint(x: cursor.x, y: cursor.y)
            cursorPixelSize = CGSize(width: max(CGFloat(cursor.width), 1), height: max(CGFloat(cursor.height), 1))
        } else {
            cursorView.isHidden = true
        }
        #if os(iOS) && !targetEnvironment(macCatalyst)
            if wasHidden != cursorView.isHidden { pointerInteraction?.invalidate() }
        #endif
        setNeedsLayout()
    }

    /// The local pointer: an arrow whose tip, the hotspot, is at the
    /// image's top-left, white with a dark edge to show on any picture.
    static let arrow: UIImage = {
        let points: [CGPoint] = [
            .init(x: 0, y: 0), .init(x: 0, y: 17), .init(x: 4.2, y: 13.2), .init(x: 7, y: 19.5),
            .init(x: 9.6, y: 18.4), .init(x: 6.9, y: 12.3), .init(x: 12.5, y: 12.3),
        ]
        let inset: CGFloat = 1.5
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 12.5 + inset * 2, height: 19.5 + inset * 2), format: format).image { context in
            let path = UIBezierPath()
            path.move(to: points[0].applying(.init(translationX: inset, y: inset)))
            for point in points.dropFirst() { path.addLine(to: point.applying(.init(translationX: inset, y: inset))) }
            path.close()
            path.lineJoinStyle = .round
            path.lineWidth = 1.5
            context.cgContext.setShadow(offset: CGSize(width: 0, height: 1), blur: 2, color: UIColor.black.withAlphaComponent(0.35).cgColor)
            UIColor.black.setStroke()
            path.stroke()
            context.cgContext.setShadow(offset: .zero, blur: 0)
            UIColor.white.setFill()
            path.fill()
        }
    }()

    /// The arrow's tip within its image.
    private static let arrowTip = CGPoint(x: 1.5, y: 1.5)

    /// Whether a pointer is drawn on the picture, the host's or ours.
    private var drawsPointer: Bool {
        !cursorView.isHidden || !localPointerView.isHidden
    }

    /// The rect the framebuffer aspect-fits into, in view coordinates.
    var imageRect: CGRect {
        let fb = framebufferSize
        guard fb.width > 0, fb.height > 0, bounds.width > 0, bounds.height > 0 else {
            return bounds
        }
        let scale = min(bounds.width / fb.width, bounds.height / fb.height)
        let size = CGSize(width: fb.width * scale, height: fb.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Where the framebuffer is drawn: `imageRect`, pinch-zoomed.
    var displayRect: CGRect {
        viewport.rect(fitting: imageRect, in: bounds)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let rect = displayRect
        frameView.frame = rect
        // Ours only on a touch screen, with a picture, and while the host
        // draws no pointer of its own.
        let showsLocal = Self.usesTouchGestures && cursorView.isHidden && framebufferSize.width > 0 && frameView.picture != nil
        if localPointerView.isHidden == showsLocal {
            localPointerView.isHidden = !showsLocal
            #if os(iOS) && !targetEnvironment(macCatalyst)
                pointerInteraction?.invalidate()
            #endif
        }
        if showsLocal {
            let size = localPointerView.image?.size ?? .zero
            localPointerView.frame = CGRect(
                x: rect.minX + lastNormalized.x * rect.width - Self.arrowTip.x,
                y: rect.minY + lastNormalized.y * rect.height - Self.arrowTip.y,
                width: size.width,
                height: size.height
            )
        }
        if !cursorView.isHidden {
            let fb = framebufferSize
            let w = fb.width > 0 ? cursorPixelSize.width * rect.width / fb.width : cursorPixelSize.width
            let h = fb.height > 0 ? cursorPixelSize.height * rect.height / fb.height : cursorPixelSize.height
            cursorView.frame = CGRect(
                x: rect.minX + cursorPosition.x * rect.width,
                y: rect.minY + cursorPosition.y * rect.height,
                width: w,
                height: h
            )
        }
    }

    // MARK: - Coordinate mapping

    /// A view point -> normalized framebuffer coordinates (0...1), clamped
    /// so presses near the letterbox edge still land inside the remote
    /// display. Returns nil while there is no framebuffer.
    private func normalizedPoint(_ location: CGPoint) -> CGPoint? {
        let rect = displayRect
        guard rect.width > 0, rect.height > 0, framebufferSize.width > 0 else { return nil }
        let nx = (location.x - rect.minX) / rect.width
        let ny = (location.y - rect.minY) / rect.height
        guard nx >= -0.05, nx <= 1.05, ny >= -0.05, ny <= 1.05 else { return nil }
        return CGPoint(x: min(max(nx, 0), 1), y: min(max(ny, 0), 1))
    }

    // MARK: - Pointer input

    @objc private func hoverMoved(_ recognizer: UIHoverGestureRecognizer) {
        guard let point = normalizedPoint(recognizer.location(in: self)) else { return }
        switch recognizer.state {
        case .began, .changed:
            lastNormalized = point
            session?.pointerMoved(normalizedX: point.x, normalizedY: point.y)
        default:
            break
        }
    }

    @objc private func pressRecognized(_ recognizer: UILongPressGestureRecognizer) {
        let point = normalizedPoint(recognizer.location(in: self)) ?? lastNormalized
        switch recognizer.state {
        case .began:
            takeKeyFocus()
            lastNormalized = point
            session?.pointerButton(.left, isDown: true, normalizedX: point.x, normalizedY: point.y)
        case .changed:
            lastNormalized = point
            session?.pointerMoved(normalizedX: point.x, normalizedY: point.y)
        case .ended, .cancelled:
            session?.pointerButton(.left, isDown: false, normalizedX: point.x, normalizedY: point.y)
        default:
            break
        }
    }

    /// Secondary/tertiary buttons: taps send down+up so context menus work.
    @objc private func clickRecognized(_ recognizer: UITapGestureRecognizer) {
        let button: MouseButton = recognizer === tertiaryPress ? .middle : .right
        guard let point = normalizedPoint(recognizer.location(in: self)) else { return }
        session?.pointerButton(button, isDown: true, normalizedX: point.x, normalizedY: point.y)
        session?.pointerButton(button, isDown: false, normalizedX: point.x, normalizedY: point.y)
    }

    @objc private func scrollPanned(_ recognizer: UIPanGestureRecognizer) {
        guard let point = normalizedPoint(recognizer.location(in: self)) else { return }
        let translation = recognizer.translation(in: self)
        recognizer.setTranslation(.zero, in: self)
        if recognizer.state == .began {
            scrollAccumX = 0
            scrollAccumY = 0
        }
        scroll(by: CGVector(dx: translation.x, dy: translation.y), at: point)
    }

    /// Turns a scroll of `delta` view points into wheel ticks at `point`.
    /// `delta.dy` follows the finger/wheel direction: positive under natural
    /// scrolling means content pulled down = scroll up, which matches the
    /// driver's "positive y = scroll up" contract.
    private func scroll(by delta: CGVector, at point: CGPoint) {
        scrollAccumX += delta.dx
        scrollAccumY += delta.dy
        var dx: Double = 0
        var dy: Double = 0
        let tickPx: CGFloat = 28
        while scrollAccumX >= tickPx { dx += 1; scrollAccumX -= tickPx }
        while scrollAccumX <= -tickPx { dx -= 1; scrollAccumX += tickPx }
        while scrollAccumY >= tickPx { dy += 1; scrollAccumY -= tickPx }
        while scrollAccumY <= -tickPx { dy -= 1; scrollAccumY += tickPx }
        guard dx != 0 || dy != 0 else { return }
        session?.scrolled(deltaX: dx, deltaY: dy, normalizedX: point.x, normalizedY: point.y)
    }

    // MARK: - Touch input

    /// The fingers among `touches`, by a stable id, where they are now. A
    /// pencil and an indirect pointer are the recognizers'.
    private func fingers(_ touches: Set<UITouch>) -> [Int: CGPoint] {
        guard Self.usesTouchGestures else { return [:] }
        var fingers: [Int: CGPoint] = [:]
        for touch in touches where touch.type == .direct {
            fingers[ObjectIdentifier(touch).hashValue] = touch.location(in: self)
        }
        return fingers
    }

    private func now(_ event: UIEvent?) -> TimeInterval {
        event?.timestamp ?? ProcessInfo.processInfo.systemUptime
    }

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let fingers = fingers(touches)
        guard !fingers.isEmpty else { return super.touchesBegan(touches, with: event) }
        takeKeyFocus()
        perform(gestures.began(fingers, at: now(event)))
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let fingers = fingers(touches)
        guard !fingers.isEmpty else { return super.touchesMoved(touches, with: event) }
        perform(gestures.moved(fingers, at: now(event)))
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let fingers = fingers(touches)
        guard !fingers.isEmpty else { return super.touchesEnded(touches, with: event) }
        perform(gestures.ended(Array(fingers.keys), at: now(event)))
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        let fingers = fingers(touches)
        guard !fingers.isEmpty else { return super.touchesCancelled(touches, with: event) }
        perform(gestures.cancelled())
    }

    /// Carries out what the touch gestures asked for.
    private func perform(_ actions: [RemoteDesktopTouchAction]) {
        for action in actions {
            switch action {
            case let .movePointer(by: delta):
                let rect = displayRect
                guard rect.width > 0, rect.height > 0, framebufferSize.width > 0 else { continue }
                lastNormalized = CGPoint(
                    x: min(max(lastNormalized.x + delta.dx / rect.width, 0), 1),
                    y: min(max(lastNormalized.y + delta.dy / rect.height, 0), 1)
                )
                session?.pointerMoved(normalizedX: lastNormalized.x, normalizedY: lastNormalized.y)
                // Zoomed in, the picture follows the pointer.
                if viewport.zoom > 1 {
                    viewport.reveal(lastNormalized, margin: 48, base: imageRect, bounds: bounds)
                    setNeedsLayout()
                }
            case let .placePointer(at: location):
                // The finger may be on the letterbox: the nearest edge.
                let rect = displayRect
                guard rect.width > 0, rect.height > 0, framebufferSize.width > 0 else { continue }
                lastNormalized = CGPoint(
                    x: min(max((location.x - rect.minX) / rect.width, 0), 1),
                    y: min(max((location.y - rect.minY) / rect.height, 0), 1)
                )
                session?.pointerMoved(normalizedX: lastNormalized.x, normalizedY: lastNormalized.y)
            case let .button(button, isDown):
                #if os(iOS) && !targetEnvironment(macCatalyst)
                    if isDown { dragFeedback.impactOccurred() }
                #endif
                session?.pointerButton(button, isDown: isDown, normalizedX: lastNormalized.x, normalizedY: lastNormalized.y)
            case let .click(button):
                session?.pointerButton(button, isDown: true, normalizedX: lastNormalized.x, normalizedY: lastNormalized.y)
                session?.pointerButton(button, isDown: false, normalizedX: lastNormalized.x, normalizedY: lastNormalized.y)
            case let .scroll(by: delta):
                scroll(by: delta, at: lastNormalized)
            case let .zoom(scale, anchor, pan):
                viewport.zoom(by: scale, anchor: anchor, pan: pan, base: imageRect, bounds: bounds)
                setNeedsLayout()
            case .toggleKeyboard:
                toggleKeyboard()
            }
        }
    }

    // MARK: - Keyboard input

    public override var canBecomeFirstResponder: Bool { true }

    #if os(iOS) && !targetEnvironment(macCatalyst)
        /// Three fingers are the desktop's: no undo or copy and paste bar.
        public override var editingInteractionConfiguration: UIEditingInteractionConfiguration { .none }

        /// Shown, the canvas takes hardware keys at once; it is no text
        /// input, so no software keyboard comes with it.
        public override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return stopKeyRepeat() }
            DispatchQueue.main.async { [weak self] in self?.takeKeyFocus() }
        }
    #endif

    /// Takes hardware keys, unless the software keyboard is up: its proxy
    /// has them then.
    private func takeKeyFocus() {
        guard !isFirstResponder, !keyboardProxy.isFirstResponder else { return }
        _ = becomeFirstResponder()
    }

    // Presses the keyboard proxy passed on come up the responder chain
    // here: the proxy already sent what is the host's, the rest is the
    // text system's.

    public override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandled = keyboardProxy.isFirstResponder ? presses : presses.filter { !hardwareKey($0, isDown: true) }
        if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
    }

    public override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandled = keyboardProxy.isFirstResponder ? presses : presses.filter { !hardwareKey($0, isDown: false) }
        if !unhandled.isEmpty { super.pressesEnded(unhandled, with: event) }
    }

    /// A press the system took back (the app went away, a gesture won)
    /// still lets go of its key on the host.
    public override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandled = keyboardProxy.isFirstResponder ? presses : presses.filter { !hardwareKey($0, isDown: false) }
        if !unhandled.isEmpty { super.pressesCancelled(unhandled, with: event) }
    }

    /// Sends a hardware key down or up as the key it is, so the host sees
    /// it held, with its modifiers, as from a keyboard of its own; a key
    /// outside the keymap can still type its text. False for a press that
    /// is no key.
    func hardwareKey(_ press: UIPress, isDown: Bool) -> Bool {
        guard let key = press.key else { return false }
        let usage = Int(key.keyCode.rawValue)
        let isModifier = usage == 0x39 || (0xE0 ... 0xE7).contains(usage)
        // A press its key command already sent: neither its down nor its up
        // goes again.
        if isDown, keysFromCommands.contains(usage) {
            pressesFromCommands.insert(press)
            return true
        }
        if !isDown, pressesFromCommands.remove(press) != nil { return true }
        if isDown {
            heldUsages.insert(usage)
            keysFromPresses.insert(usage)
            DispatchQueue.main.async { [weak self] in self?.keysFromPresses.remove(usage) }
        } else {
            heldUsages.remove(usage)
        }
        // Only the last key repeats, as on every desktop; a modifier going
        // down leaves the repeat alone.
        if isDown, !isModifier { stopKeyRepeat() }
        if !isDown, press === keyRepeat?.press { stopKeyRepeat() }
        guard let stroke = RemoteDesktopKeymap.stroke(hidUsage: usage, typing: Self.keySymText(key), isDown: isDown) else {
            if isDown, VNCKeySyms.keySym(forCharacter: key.characters) != nil { session?.typeText(key.characters) }
            return true
        }
        session?.sendKeys([stroke])
        if isDown, !isModifier, !key.modifierFlags.contains(.command) { startKeyRepeat(press, stroke) }
        if !isDown, !isModifier { releaseArmedModifiers() }
        return true
    }

    /// Keys iPadOS keeps for itself (Tab and the arrows move focus, Escape
    /// dismisses, Home and End scroll, Backspace goes back) unless a key
    /// command claims them first; such a command may come instead of the
    /// press or with it, depending on the iPadOS version. While the
    /// software keyboard is up, Backspace and Return are the input
    /// method's.
    public override var keyCommands: [UIKeyCommand]? {
        if keyboardProxy.markedTextRange != nil { return nil }
        let typing = keyboardProxy.isFirstResponder
        let modifiers: [UIKeyModifierFlags] = [[], .shift, .control, .alternate, .command, [.control, .alternate], [.control, .shift]]
        return Self.systemKeys.filter { !typing || !$0.typed }.flatMap { key in
            modifiers.map { flags in
                let command = UIKeyCommand(input: key.input, modifierFlags: flags, action: #selector(systemKeyCommand(_:)))
                command.wantsPriorityOverSystemBehavior = true
                return command
            }
        }
    }

    private static let systemKeys: [(input: String, usage: Int, typed: Bool)] = [
        (UIKeyCommand.inputEscape, 0x29, false),
        ("\t", 0x2B, false),
        ("\u{8}", 0x2A, true),
        ("\r", 0x28, true),
        (UIKeyCommand.inputHome, 0x4A, false),
        (UIKeyCommand.inputEnd, 0x4D, false),
        (UIKeyCommand.inputPageUp, 0x4B, false),
        (UIKeyCommand.inputPageDown, 0x4E, false),
        (UIKeyCommand.inputDelete, 0x4C, false),
        (UIKeyCommand.inputUpArrow, 0x52, false),
        (UIKeyCommand.inputDownArrow, 0x51, false),
        (UIKeyCommand.inputLeftArrow, 0x50, false),
        (UIKeyCommand.inputRightArrow, 0x4F, false),
    ]

    /// A claimed key, unless its press already went down: sent as a click,
    /// and its press, if one follows this turn, sends nothing more.
    @objc private func systemKeyCommand(_ command: UIKeyCommand) {
        guard let usage = Self.systemKeys.first(where: { $0.input == command.input })?.usage,
              !heldUsages.contains(usage), !keysFromPresses.contains(usage),
              let stroke = RemoteDesktopKeymap.stroke(hidUsage: usage, typing: "", isDown: true)
        else { return }
        keysFromCommands.insert(usage)
        DispatchQueue.main.async { [weak self] in self?.keysFromCommands.remove(usage) }
        sendKey(stroke)
    }

    /// The text a key's KeySym names: what it types with Shift but without
    /// Ctrl, Option or Command. UIKit's `charactersIgnoringModifiers` drops
    /// Shift too, and a VNC server types the KeySym it gets exactly, letting
    /// go of a held Shift to make Shift+A an a.
    private static func keySymText(_ key: UIKey) -> String {
        guard key.modifierFlags.isDisjoint(with: [.control, .alternate, .command]) else {
            let text = key.charactersIgnoringModifiers
            return key.modifierFlags.contains(.shift) && text.count == 1 ? text.uppercased() : text
        }
        return key.characters
    }

    /// UIKit reports a held key once; the repeat is the text system's,
    /// which these keys never reach. The host repeats a key whose down
    /// comes again (RFB leaves the repeat to the client), so a held key
    /// sends its down again, at AppKit's default rate: iPadOS shows no
    /// app the user's own.
    private func startKeyRepeat(_ press: UIPress, _ stroke: RemoteDesktopKeyStroke) {
        let task = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(400))
                while let session = self?.session {
                    session.sendKeys([stroke])
                    try await Task.sleep(for: .milliseconds(50))
                }
            } catch {}
        }
        keyRepeat = (press, task)
    }

    private func stopKeyRepeat() {
        keyRepeat?.task.cancel()
        keyRepeat = nil
    }

    // MARK: - Software keyboard

    /// Toggles the software keyboard when the request counter changes.
    func applyKeyboardRequest(_ requests: Int) {
        guard requests != appliedKeyboardRequests else { return }
        appliedKeyboardRequests = requests
        toggleKeyboard()
    }

    /// Takes `requests` as answered, without touching the keyboard.
    func syncKeyboardRequests(_ requests: Int) {
        appliedKeyboardRequests = requests
    }

    /// Brings the software keyboard up (its proxy takes focus), or puts it
    /// away and takes hardware keys again.
    func toggleKeyboard() {
        if keyboardProxy.isFirstResponder {
            hideKeyboard()
        } else {
            _ = keyboardProxy.becomeFirstResponder()
        }
    }

    /// Puts the software keyboard away; the bar's modifiers let go with it.
    func hideKeyboard() {
        releaseModifiers()
        _ = keyboardProxy.resignFirstResponder()
        _ = becomeFirstResponder()
    }

    /// The keys a touch keyboard lacks, over it.
    lazy var keyboardAccessory = RemoteDesktopKeyboardBar(canvas: self)

    // MARK: - Sticky modifiers

    /// The bar's modifiers are down on the host while they show active, so
    /// a click or a key from anywhere takes them along.
    private var stickyModifiers = RemoteDesktopStickyModifiers()

    var hasStickyModifiers: Bool { !stickyModifiers.active.isEmpty }

    func modifierActivation(_ modifier: RemoteDesktopStickyModifiers.Modifier) -> RemoteDesktopStickyModifiers.Activation {
        stickyModifiers[modifier]
    }

    func tapModifier(_ modifier: RemoteDesktopStickyModifiers.Modifier) {
        let wasDown = stickyModifiers[modifier] != .inactive
        let isDown = stickyModifiers.tap(modifier, at: CACurrentMediaTime()) != .inactive
        if isDown != wasDown { session?.sendKeys([modifier.stroke.with(isDown: isDown)]) }
        keyboardAccessory.refresh()
    }

    /// A key was sent: the modifiers held for it let go.
    private func releaseArmedModifiers() {
        let released = stickyModifiers.consume()
        guard !released.isEmpty else { return }
        session?.sendKeys(released.reversed().map { $0.stroke.with(isDown: false) })
        keyboardAccessory.refresh()
    }

    func releaseModifiers() {
        let released = stickyModifiers.reset()
        guard !released.isEmpty else { return }
        session?.sendKeys(released.reversed().map { $0.stroke.with(isDown: false) })
        keyboardAccessory.refresh()
    }

    /// A key from the bar, pressed and let go under the bar's modifiers.
    func sendKey(_ key: RemoteDesktopKeyStroke) {
        sendKeys(RemoteDesktopSpecialKeys.click(key))
    }

    func sendKeys(_ strokes: [RemoteDesktopKeyStroke]) {
        session?.sendKeys(strokes)
        releaseArmedModifiers()
    }

    // MARK: - Typed text

    /// Text from the software keyboard. Under a modifier of the bar it is
    /// a combination, so each character goes as the key that types it.
    func insertTyped(_ text: String) {
        guard hasStickyModifiers || text == "\n" || text == "\r" else {
            session?.typeText(text)
            return
        }
        // Under the bar's Shift a letter is a capital, whatever the touch
        // keyboard's own Shift: a VNC server types the KeySym it gets
        // exactly, letting go of Shift for a small one.
        let shifted = stickyModifiers[.shift] != .inactive
        var strokes: [RemoteDesktopKeyStroke] = []
        for character in shifted ? text.uppercased() : text {
            guard let (key, shift) = RemoteDesktopKeymap.key(typing: character) else {
                session?.sendKeys(strokes)
                strokes = []
                session?.typeText(String(character))
                continue
            }
            let needsShift = shift && !shifted
            strokes += needsShift ? RemoteDesktopSpecialKeys.combo([RemoteDesktopSpecialKeys.shift], key) : RemoteDesktopSpecialKeys.click(key)
        }
        sendKeys(strokes)
    }

    func deleteTypedBackward() {
        sendKey(RemoteDesktopSpecialKeys.backspace)
    }
}

#if os(iOS) && !targetEnvironment(macCatalyst)
    extension RemoteDesktopCanvasView: UIPointerInteractionDelegate {
        /// A pointer is drawn over the picture (the host's, or ours): the
        /// iPad's own would be a second one. The host's drawn off the view
        /// shows nothing, so the iPad's stays then.
        public func pointerInteraction(_: UIPointerInteraction, styleFor _: UIPointerRegion) -> UIPointerStyle? {
            guard drawsPointer else { return nil }
            if !cursorView.isHidden, !bounds.intersects(cursorView.frame) { return nil }
            return .hidden()
        }
    }
#endif

#elseif canImport(AppKit)
import AppKit

/// SwiftUI shell around `RemoteDesktopCanvasNSView` on native macOS.
public struct RemoteDesktopCanvas: NSViewRepresentable {
    @ObservedObject public var session: RemoteDesktopSession
    public var keyboardRequests: Int
    /// A Mac has no touch screen: kept for the shared stage only.
    public var touchMode: RemoteDesktopTouchMode

    public init(session: RemoteDesktopSession, keyboardRequests: Int = 0, touchMode: RemoteDesktopTouchMode = .trackpad) {
        self.session = session
        self.keyboardRequests = keyboardRequests
        self.touchMode = touchMode
    }

    public func makeNSView(context _: Context) -> RemoteDesktopCanvasNSView {
        let view = RemoteDesktopCanvasNSView()
        view.follow(session)
        return view
    }

    public static func dismantleNSView(_ view: RemoteDesktopCanvasNSView, coordinator _: ()) {
        view.session?.stopObservingFrames(by: view)
    }

    public func updateNSView(_ view: RemoteDesktopCanvasNSView, context _: Context) {
        if view.session !== session { view.follow(session) }
    }
}

/// AppKit backend: `mouseMoved` via a tracking area, button events from
/// the responder chain, `scrollWheel` deltas, and `keyDown`/`flagsChanged`
/// which already report Carbon virtual keycodes.
public final class RemoteDesktopCanvasNSView: NSView {
    public var session: RemoteDesktopSession?

    /// Shows the pictures: each IOSurface goes on screen as it is.
    private let frameView = RemoteDesktopFrameView()
    private let cursorView = NSImageView()
    private var framebufferSize: CGSize = .zero
    private var cursorPosition = CGPoint.zero
    private var cursorPixelSize = CGSize.zero
    private var scrollAccumX: CGFloat = 0
    private var scrollAccumY: CGFloat = 0
    private var lastNormalized = CGPoint(x: 0.5, y: 0.5)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        addSubview(frameView)
        cursorView.isHidden = true
        addSubview(cursorView)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved],
            owner: self,
            userInfo: nil
        ))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public override var acceptsFirstResponder: Bool { true }
    public override var isFlipped: Bool { true }

    /// Draws `session`'s frames and cursor as they come, straight from it.
    func follow(_ session: RemoteDesktopSession) {
        if let previous = self.session, previous !== session { previous.stopObservingFrames(by: self) }
        self.session = session
        session.observeFrames(
            by: self,
            frame: { [weak self] picture, size in self?.applyFrame(picture, framebufferSize: size) },
            cursor: { [weak self] cursor in self?.applyCursor(cursor) }
        )
        applyFrame(session.framePicture, framebufferSize: session.framebufferSize)
        applyCursor(session.remoteCursor)
    }

    func applyFrame(_ picture: RemoteDesktopPicture?, framebufferSize: CGSize) {
        if let picture { frameView.show(picture) }
        guard framebufferSize != self.framebufferSize else { return }
        self.framebufferSize = framebufferSize
        needsLayout = true
    }

    func applyCursor(_ cursor: RemoteCursorInfo?) {
        if let cursor, cursor.visible, let image = cursor.image {
            cursorView.image = NSImage(cgImage: image, size: .zero)
            cursorView.isHidden = false
            cursorPosition = CGPoint(x: cursor.x, y: cursor.y)
            cursorPixelSize = CGSize(width: max(CGFloat(cursor.width), 1), height: max(CGFloat(cursor.height), 1))
        } else {
            cursorView.isHidden = true
        }
        needsLayout = true
    }

    var imageRect: CGRect {
        let fb = framebufferSize
        guard fb.width > 0, fb.height > 0, bounds.width > 0, bounds.height > 0 else {
            return bounds
        }
        let scale = min(bounds.width / fb.width, bounds.height / fb.height)
        let size = CGSize(width: fb.width * scale, height: fb.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    public override func layout() {
        super.layout()
        frameView.frame = imageRect
        if !cursorView.isHidden {
            let rect = imageRect
            let fb = framebufferSize
            let w = fb.width > 0 ? cursorPixelSize.width * rect.width / fb.width : cursorPixelSize.width
            let h = fb.height > 0 ? cursorPixelSize.height * rect.height / fb.height : cursorPixelSize.height
            cursorView.frame = CGRect(
                x: rect.minX + cursorPosition.x * rect.width,
                y: rect.minY + cursorPosition.y * rect.height,
                width: w,
                height: h
            )
        }
    }

    private func normalizedPoint(_ event: NSEvent) -> CGPoint? {
        let location = convert(event.locationInWindow, from: nil)
        let rect = imageRect
        guard rect.width > 0, rect.height > 0, framebufferSize.width > 0 else { return nil }
        let nx = (location.x - rect.minX) / rect.width
        let ny = (location.y - rect.minY) / rect.height
        guard nx >= -0.05, nx <= 1.05, ny >= -0.05, ny <= 1.05 else { return nil }
        return CGPoint(x: min(max(nx, 0), 1), y: min(max(ny, 0), 1))
    }

    public override func mouseMoved(with event: NSEvent) {
        guard let point = normalizedPoint(event) else { return }
        lastNormalized = point
        session?.pointerMoved(normalizedX: point.x, normalizedY: point.y)
    }

    private func buttonEvent(_ button: MouseButton, isDown: Bool, event: NSEvent) {
        let point = normalizedPoint(event) ?? lastNormalized
        window?.makeFirstResponder(self)
        session?.pointerButton(button, isDown: isDown, normalizedX: point.x, normalizedY: point.y)
    }

    private func dragEvent(_ event: NSEvent) {
        guard let point = normalizedPoint(event) else { return }
        lastNormalized = point
        session?.pointerMoved(normalizedX: point.x, normalizedY: point.y)
    }

    public override func mouseDown(with event: NSEvent) { buttonEvent(.left, isDown: true, event: event) }
    public override func mouseUp(with event: NSEvent) { buttonEvent(.left, isDown: false, event: event) }
    public override func mouseDragged(with event: NSEvent) { dragEvent(event) }
    public override func rightMouseDown(with event: NSEvent) { buttonEvent(.right, isDown: true, event: event) }
    public override func rightMouseUp(with event: NSEvent) { buttonEvent(.right, isDown: false, event: event) }
    public override func rightMouseDragged(with event: NSEvent) { dragEvent(event) }
    public override func otherMouseDown(with event: NSEvent) {
        buttonEvent(event.buttonNumber == 2 ? .middle : event.buttonNumber == 3 ? .back : .forward, isDown: true, event: event)
    }
    public override func otherMouseUp(with event: NSEvent) {
        buttonEvent(event.buttonNumber == 2 ? .middle : event.buttonNumber == 3 ? .back : .forward, isDown: false, event: event)
    }
    public override func otherMouseDragged(with event: NSEvent) { dragEvent(event) }

    public override func scrollWheel(with event: NSEvent) {
        guard let point = normalizedPoint(event) else { return }
        // `deltaY > 0` is scroll up in NSEvent, matching the driver
        // contract; precise trackpad deltas accumulate into wheel ticks.
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 28 : 1
        scrollAccumX += event.scrollingDeltaX * scale
        scrollAccumY += event.scrollingDeltaY * scale
        var dx: Double = 0
        var dy: Double = 0
        while scrollAccumX >= 28 { dx += 1; scrollAccumX -= 28 }
        while scrollAccumX <= -28 { dx -= 1; scrollAccumX += 28 }
        while scrollAccumY >= 28 { dy += 1; scrollAccumY -= 28 }
        while scrollAccumY <= -28 { dy -= 1; scrollAccumY += 28 }
        guard dx != 0 || dy != 0 else { return }
        session?.scrolled(deltaX: dx, deltaY: dy, normalizedX: point.x, normalizedY: point.y)
    }

    public override func keyDown(with event: NSEvent) {
        forward(event, isDown: true)
    }

    public override func keyUp(with event: NSEvent) {
        forward(event, isDown: false)
    }

    /// Modifier transitions come through `flagsChanged`, not `keyDown`.
    public override func flagsChanged(with event: NSEvent) {
        let keyCode = event.keyCode
        let down: Bool = switch keyCode {
        case 56, 60: event.modifierFlags.contains(.shift)
        case 58, 61: event.modifierFlags.contains(.option)
        case 59, 62: event.modifierFlags.contains(.control)
        case 55, 54: event.modifierFlags.contains(.command)
        case 57: event.modifierFlags.contains(.capsLock)
        default: false
        }
        let characters = event.characters ?? ""
        let keySym = VNCKeySyms.keySym(forKeyCode: keyCode, characters: characters)
        session?.keyPressed(keyCode: keyCode, keySym: keySym, characters: characters, isDown: down)
    }

    private func forward(_ event: NSEvent, isDown: Bool) {
        guard let session else { return }
        let characters = event.characters ?? ""
        let modifiers = event.modifierFlags
        if !characters.isEmpty,
           !modifiers.contains(.control), !modifiers.contains(.command), !modifiers.contains(.option)
        {
            if isDown { session.typeText(characters) }
            return
        }
        let keySym = VNCKeySyms.keySym(forKeyCode: event.keyCode, characters: event.charactersIgnoringModifiers ?? "")
        session.keyPressed(keyCode: event.keyCode, keySym: keySym, characters: characters, isDown: isDown)
    }

    /// Text input from the IME path (NSView is a text-input client through
    /// `NSTextInputClient` defaults; plain `keyDown` covers ASCII).
    public override func insertText(_ insertString: Any) {
        if let string = insertString as? String {
            session?.typeText(string)
        }
    }

    public override func doCommand(by selector: Selector) {
        switch selector {
        case #selector(NSResponder.deleteBackward(_:)):
            session?.keyPressed(keyCode: 51, keySym: 0xFF08, characters: "\u{7F}", isDown: true)
            session?.keyPressed(keyCode: 51, keySym: 0xFF08, characters: "\u{7F}", isDown: false)
        case #selector(NSResponder.deleteForward(_:)):
            session?.keyPressed(keyCode: 117, keySym: 0xFFFF, characters: "", isDown: true)
            session?.keyPressed(keyCode: 117, keySym: 0xFFFF, characters: "", isDown: false)
        case #selector(NSResponder.insertNewline(_:)):
            session?.keyPressed(keyCode: 36, keySym: 0xFF0D, characters: "\r", isDown: true)
            session?.keyPressed(keyCode: 36, keySym: 0xFF0D, characters: "\r", isDown: false)
        default:
            super.doCommand(by: selector)
        }
    }
}
#endif
