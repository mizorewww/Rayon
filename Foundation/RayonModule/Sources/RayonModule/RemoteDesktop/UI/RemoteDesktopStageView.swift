//
//  RemoteDesktopStageView.swift
//  RayonModule
//
//  The remote-desktop stage shared by the macOS session page and the iOS
//  modal: the canvas, a floating control bar, and the status overlays for
//  connecting / closed / failed phases.
//

import RayonDesign
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// A key-combination entry in the stage's Special Keys menu: the strokes
/// are replayed verbatim (modifier down, key click, modifiers up).
public struct RemoteDesktopKeyStroke: Sendable {
    public let keyCode: UInt16
    public let keySym: UInt32?
    public let characters: String
    public let isDown: Bool

    public init(keyCode: UInt16, keySym: UInt32?, characters: String = "", isDown: Bool) {
        self.keyCode = keyCode
        self.keySym = keySym
        self.characters = characters
        self.isDown = isDown
    }
}

/// Special-key sequences every target understands, encoded as Carbon
/// keycodes (macOS targets) plus X11 KeySyms (VNC). Windows UU targets get
/// the Carbon codes translated by the driver.
public enum RemoteDesktopSpecialKeys {
    public static let escape = RemoteDesktopKeyStroke(keyCode: 53, keySym: 0xFF1B, isDown: true)
    public static let tab = RemoteDesktopKeyStroke(keyCode: 48, keySym: 0xFF09, isDown: true)
    public static let backspace = RemoteDesktopKeyStroke(keyCode: 51, keySym: 0xFF08, isDown: true)
    public static let `return` = RemoteDesktopKeyStroke(keyCode: 36, keySym: 0xFF0D, isDown: true)
    public static let deleteForward = RemoteDesktopKeyStroke(keyCode: 117, keySym: 0xFFFF, isDown: true)
    public static let insert = RemoteDesktopKeyStroke(keyCode: 114, keySym: 0xFF63, isDown: true)
    public static let home = RemoteDesktopKeyStroke(keyCode: 115, keySym: 0xFF50, isDown: true)
    public static let end = RemoteDesktopKeyStroke(keyCode: 119, keySym: 0xFF57, isDown: true)
    public static let pageUp = RemoteDesktopKeyStroke(keyCode: 116, keySym: 0xFF55, isDown: true)
    public static let pageDown = RemoteDesktopKeyStroke(keyCode: 121, keySym: 0xFF56, isDown: true)
    public static let left = RemoteDesktopKeyStroke(keyCode: 123, keySym: 0xFF51, isDown: true)
    public static let up = RemoteDesktopKeyStroke(keyCode: 126, keySym: 0xFF52, isDown: true)
    public static let right = RemoteDesktopKeyStroke(keyCode: 124, keySym: 0xFF53, isDown: true)
    public static let down = RemoteDesktopKeyStroke(keyCode: 125, keySym: 0xFF54, isDown: true)

    public static let control = RemoteDesktopKeyStroke(keyCode: 59, keySym: 0xFFE3, isDown: true)
    public static let shift = RemoteDesktopKeyStroke(keyCode: 56, keySym: 0xFFE1, isDown: true)
    public static let alt = RemoteDesktopKeyStroke(keyCode: 58, keySym: 0xFFE9, isDown: true)
    public static let `super` = RemoteDesktopKeyStroke(keyCode: 55, keySym: 0xFFEB, isDown: true)

    /// F1...F12 — Carbon keycodes 122, 120, 99, 118, 96-100, 101, 109, 103, 111.
    public static func functionKey(_ n: Int) -> RemoteDesktopKeyStroke {
        let codes: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        guard n >= 1, n <= 12 else {
            return RemoteDesktopKeyStroke(keyCode: 0, keySym: nil, isDown: true)
        }
        return RemoteDesktopKeyStroke(keyCode: codes[n - 1], keySym: 0xFFBE + UInt32(n - 1), isDown: true)
    }

    /// Ctrl+Alt+Del: the Windows secure attention sequence.
    public static var ctrlAltDelete: [RemoteDesktopKeyStroke] {
        combo([control, alt], deleteForward)
    }

    /// Expands a key into a down+up pair.
    public static func click(_ key: RemoteDesktopKeyStroke) -> [RemoteDesktopKeyStroke] {
        [
            key,
            RemoteDesktopKeyStroke(keyCode: key.keyCode, keySym: key.keySym, characters: key.characters, isDown: false),
        ]
    }

    /// Expands a held-modifier combo into the full down/click/up sequence.
    public static func combo(
        _ modifiers: [RemoteDesktopKeyStroke],
        _ key: RemoteDesktopKeyStroke
    ) -> [RemoteDesktopKeyStroke] {
        modifiers
            + click(key)
            + modifiers.reversed().map {
                RemoteDesktopKeyStroke(keyCode: $0.keyCode, keySym: $0.keySym, isDown: false)
            }
    }
}

/// The stage: a remote canvas plus a floating control bar. Used inside
/// `RemoteDesktopPage` on macOS and the presentation queue on iOS.
public struct RemoteDesktopStageView: View {
    @ObservedObject public var session: RemoteDesktopSession
    /// Optional host-provided close action; rendered as the last control.
    public var onClose: (() -> Void)?

    @State private var keyboardRequests = 0
    @State private var showsTextInput = false
    @State private var textDraft = ""
    @State private var toast: String?
    /// The touch gestures were explained for this session.
    @State private var gestureHintShown = false
    /// Asked once: the bar is drawn again for every frame, and each ask is
    /// a trip to the system.
    @State private var officialAppInstalled = false
    /// How fingers drive the pointer, kept on this device for every desktop.
    @AppSetting(AppSettings.remoteDesktopTouchMode) private var touchMode
    /// The screen's size in pixels: what a virtual display is made at.
    @State private var stagePixels = CGSize(width: 1920, height: 1080)
    @Environment(\.displayScale) private var displayScale

    public init(session: RemoteDesktopSession, onClose: (() -> Void)? = nil) {
        self.session = session
        self.onClose = onClose
    }

    /// The bar above the screen, never over it; the screen takes the rest.
    public var body: some View {
        VStack(spacing: 0) {
            controlBar
            ZStack { canvasLayer }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .background {
                    GeometryReader { proxy in
                        Color.clear.onAppear { measure(proxy.size) }
                            .onChange(of: proxy.size) { measure($0) }
                    }
                }
        }
        .background(Color.black.ignoresSafeArea())
        .onChange(of: session.notice) { notice in
            if let notice { flash(notice.text, for: 4) }
        }
        #if os(iOS)
            .onAppear {
                if session.protocolType == .uuRemote { officialAppInstalled = UULocalBridge.officialAppInstalled }
            }
        #endif
        .overlay(alignment: .bottom) {
            // The stage is black in both appearances: white on a dark
            // capsule, never a material that follows Light mode.
            if let toast {
                Text(toast)
                    .font(.rxCaption)
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.78), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18)))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        #if os(iOS) && !targetEnvironment(macCatalyst)
            // Once a session: a UU host going locked and back is no new
            // connection.
            .onChange(of: session.phase == .connected) { connected in
                guard connected, !gestureHintShown else { return }
                gestureHintShown = true
                showGestureHint()
            }
        #endif
    }

    // MARK: - Canvas + status overlays

    @ViewBuilder private var canvasLayer: some View {
        RemoteDesktopCanvas(session: session, keyboardRequests: keyboardRequests, touchMode: touchMode)
        switch session.phase {
        case .connected:
            EmptyView()
        case .idle:
            statusOverlay(symbol: "display", title: .init("Ready", bundle: .module), detail: session.statusHint)
        case let .connecting(detail):
            statusOverlay(
                symbol: "arrow.triangle.2.circlepath",
                title: .init("Connecting", bundle: .module),
                detail: session.statusHint.isEmpty ? detail : session.statusHint,
                spinning: true
            )
        case .authenticating:
            statusOverlay(
                symbol: "lock.shield",
                title: .init("Authenticating", bundle: .module),
                detail: session.statusHint,
                spinning: true
            )
        case let .closed(reason):
            statusOverlay(
                symbol: "display.trianglebadge.exclamationmark",
                title: .init("Session closed", bundle: .module),
                detail: reason ?? session.statusHint,
                reconnectable: true
            )
        case let .failed(message):
            statusOverlay(
                symbol: "exclamationmark.triangle",
                title: .init("Remote desktop failed", bundle: .module),
                detail: session.statusHint.isEmpty ? message : "\(message)\n\(session.statusHint)",
                reconnectable: true
            )
        }
    }

    @ViewBuilder
    private func statusOverlay(
        symbol: String,
        title: LocalizedStringResource,
        detail: String,
        spinning: Bool = false,
        reconnectable: Bool = false
    ) -> some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 10) {
                if spinning {
                    ProgressView()
                        .controlSize(.large)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.headline)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                if reconnectable {
                    Button(.init("Reconnect", bundle: .module)) { session.connect() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .foregroundStyle(.white)
        }
        .ignoresSafeArea()
        .allowsHitTesting(true)
    }

    // MARK: - Control bar

    /// On a touch screen the bar is taller, every control is a finger-sized
    /// target named under its symbol, and what does not fit scrolls
    /// sideways; More and Close stay at the end. On the Mac Connect and
    /// Close do.
    #if os(iOS) && !targetEnvironment(macCatalyst)
        static let barHeight: CGFloat = 56
        static let controlFont = Font.system(size: 17)
    #else
        static let barHeight: CGFloat = 34
        static let controlFont = Font.system(size: 13)
    #endif

    private var controlBar: some View {
        HStack(spacing: 4) {
            #if os(iOS) && !targetEnvironment(macCatalyst)
                touchStatus
                Divider().frame(height: 28)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) { touchControls }
                        .padding(.trailing, 12)
                }
                // Controls past the edge fade out rather than end cut off:
                // the row scrolls.
                .mask(
                    HStack(spacing: 0) {
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 16)
                    }
                )
                Divider().frame(height: 28)
                moreMenu
            #else
                controls
                Spacer(minLength: 8)
                connectButton
            #endif
            if let onClose {
                Button { onClose() } label: {
                    Label(.init("Close", bundle: .module), systemImage: "xmark.circle").stageControl()
                }
                .help(.init("Close this session", bundle: .module))
            }
        }
        .buttonStyle(.borderless)
        .font(Self.controlFont)
        .foregroundStyle(Color.rxInk)
        .padding(.horizontal, 10)
        .frame(height: Self.barHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.rxSurface)
        .overlay(alignment: .bottom) { Color.rxHairline.frame(height: 1) }
    }

    #if os(iOS) && !targetEnvironment(macCatalyst)
        /// What the bar's state is, in two short lines: the phase (or the
        /// desktop's name) and the frame rate and round trip.
        private var touchStatus: some View {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    StatusDot(status)
                    Text(phaseTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.rxInk)
                        .lineLimit(1)
                }
                // View only must show: input going nowhere looks broken.
                if session.viewOnly {
                    Label(.init("View only", bundle: .module), systemImage: "eye")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.rxAccent)
                        .lineLimit(1)
                } else if !metricsText.isEmpty {
                    Text(metricsText)
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(Color.rxInkSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: 104, alignment: .leading)
            .accessibilityElement(children: .combine)
        }

        /// The controls a finger needs at hand, each named under its symbol.
        @ViewBuilder private var touchControls: some View {
            Button { keyboardRequests += 1 } label: {
                Label(.init("Keyboard", bundle: .module), systemImage: "keyboard").stageControl()
            }
            specialKeysMenu
            touchModeMenu
            Button { showsTextInput = true } label: {
                Label(.init("Type", bundle: .module), systemImage: "textformat").stageControl()
            }
            .popover(isPresented: $showsTextInput) { textInputPopover }
            clipboardMenu
        }

        /// Everything used now and then, by name.
        private var moreMenu: some View {
            Menu {
                if session.phase.isTerminal || session.phase == .idle {
                    Button { session.connect() } label: { Label(.init("Connect", bundle: .module), systemImage: "play.circle") }
                } else {
                    Button { session.disconnect() } label: { Label(.init("Disconnect", bundle: .module), systemImage: "stop.circle") }
                }
                Button { session.refresh() } label: { Label(.init("Refresh Screen", bundle: .module), systemImage: "arrow.clockwise") }
                Toggle(isOn: $session.viewOnly) {
                    Label(.init("View Only", bundle: .module), systemImage: "eye")
                }
                if session.displays.count > 1 || session.canAddDisplays {
                    Menu {
                        displayChoices
                    } label: {
                        Label(.init("Display", bundle: .module), systemImage: "rectangle.on.rectangle")
                    }
                }
                if session.protocolType == .uuRemote {
                    Menu {
                        qualityChoices
                    } label: {
                        Label(.init("Quality", bundle: .module), systemImage: "slider.horizontal.3")
                    }
                    Menu {
                        officialAppChoices
                    } label: {
                        Label(.init("UU Remote App", bundle: .module), systemImage: "pip")
                    }
                }
                Section {
                    Button { showGestureHint(force: true) } label: { Label(.init("Touch Gestures", bundle: .module), systemImage: "hand.tap") }
                }
            } label: {
                Label(.init("More", bundle: .module), systemImage: "ellipsis.circle").stageControl()
            }
        }

        /// How fingers work, the first few times a desktop connects, or
        /// when asked for.
        private func showGestureHint(force: Bool = false) {
            let shown = AppSettings.remoteDesktopGestureHintsShown.value
            guard force || shown < 3 else { return }
            if !force { AppSettings.remoteDesktopGestureHintsShown.set(shown + 1) }
            let hint = switch touchMode {
            case .trackpad: String(localized: "Drag to move the pointer · tap to click · two fingers to scroll or right-click · three fingers for the keyboard", bundle: .module)
            case .direct: String(localized: "Tap to click there · hold to right-click · two fingers to scroll · three fingers for the keyboard", bundle: .module)
            }
            flash(hint, for: 5)
        }
    #endif

    @ViewBuilder private var controls: some View {
        statusPill
        Divider().frame(height: 16)
        Text(metricsText)
            .font(.rxCaption)
            .foregroundStyle(Color.rxInkSecondary)
            .lineLimit(1)
        Divider().frame(height: 16)
        if session.displays.count > 1 || session.canAddDisplays { displayMenu }
        if session.protocolType == .uuRemote { qualityMenu }
        viewOnlyButton
        specialKeysMenu
        Button { showsTextInput = true } label: {
            Label(.init("Type Text", bundle: .module), systemImage: "textformat").stageControl()
        }
        .popover(isPresented: $showsTextInput) { textInputPopover }
        #if !targetEnvironment(macCatalyst)
            // A Mac has a keyboard; a touch screen shows one on request.
            Button { keyboardRequests += 1 } label: {
                Label(.init("Software Keyboard", bundle: .module), systemImage: "keyboard").stageControl()
            }
            .help(.init("Toggle the software keyboard", bundle: .module))
        #endif
        #if os(iOS) && !targetEnvironment(macCatalyst)
            touchModeMenu
        #endif
        clipboardMenu
        Button { session.refresh() } label: {
            Label(.init("Refresh Screen", bundle: .module), systemImage: "arrow.clockwise").stageControl()
        }
        .help(.init("Ask the host for a full refresh", bundle: .module))
        #if !targetEnvironment(macCatalyst)
            if session.protocolType == .uuRemote { officialAppMenu }
        #endif
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            StatusDot(status)
            Text(phaseTitle)
                .font(.rxCaption)
                .foregroundStyle(Color.rxInkSecondary)
        }
    }

    private var status: RXStatus {
        switch session.phase {
        case .connected: .success
        case .idle: .off
        case .connecting, .authenticating: .running
        case .closed: .warning
        case .failed: .danger
        }
    }

    private var phaseTitle: String {
        switch session.phase {
        case .idle: String(localized: "Idle", bundle: .module)
        case .connecting: String(localized: "Connecting", bundle: .module)
        case .authenticating: String(localized: "Authenticating", bundle: .module)
        case .connected: session.desktopName.isEmpty ? String(localized: "Connected", bundle: .module) : session.desktopName
        case .closed: String(localized: "Closed", bundle: .module)
        case .failed: String(localized: "Failed", bundle: .module)
        }
    }

    private var metricsText: String {
        var parts: [String] = []
        if session.fps > 0 { parts.append(String(localized: "\(session.fps) fps", bundle: .module)) }
        if let rtt = session.rttMs { parts.append(String(localized: "\(rtt) ms", bundle: .module)) }
        if let network = session.network, session.phase == .connected {
            if let bits = network.bitsPerSecond { parts.append(Self.rate(bits)) }
            if let loss = network.lossPercent, loss >= 0.5 { parts.append(String(format: String(localized: "%.0f%% loss", bundle: .module), loss)) }
            if network.relayed { parts.append(String(localized: "relay", bundle: .module)) }
        }
        if !session.statusHint.isEmpty, session.phase != .connected {
            parts.append(session.statusHint)
        }
        return parts.joined(separator: " · ")
    }

    private var displayMenu: some View {
        Menu {
            displayChoices
        } label: {
            Label(.init("Display", bundle: .module), systemImage: "rectangle.on.rectangle").stageControl()
        }
        .help(.init("Switch display", bundle: .module))
    }

    @ViewBuilder private var displayChoices: some View {
            Section {
                ForEach(session.displays) { display in
                    Button {
                        session.switchDisplay(display.id)
                    } label: {
                        let title = display.name.isEmpty ? String(localized: "Display \(display.id)", bundle: .module) : display.name
                        if display.id == session.selectedDisplayID {
                            Label(title, systemImage: "checkmark")
                        } else {
                            Text(title)
                        }
                    }
                }
            }
            if session.displays.count > 1 {
                Button { session.nextDisplay() } label: {
                    Label(.init("Next Display", bundle: .module), systemImage: "arrow.right.square")
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
            }
            if session.canAddDisplays {
                Section {
                    Button {
                        session.addVirtualDisplay(width: Int(stagePixels.width), height: Int(stagePixels.height))
                    } label: {
                        Label(.init("Add Virtual Display", bundle: .module), systemImage: "plus.rectangle.on.rectangle")
                    }
                    ForEach(session.displays.filter(\.isVirtual)) { display in
                        Button(role: .destructive) {
                            session.removeVirtualDisplay(display.id)
                        } label: {
                            Label(.init("Remove \(display.name)", bundle: .module), systemImage: "minus.rectangle")
                        }
                        .disabled(session.displays.count < 2)
                    }
                }
            }
    }

    /// A virtual display is made the size of the stage, in even pixels.
    private func measure(_ size: CGSize) {
        let scale = max(displayScale, 1)
        let width = (Int(size.width * scale) / 2) * 2
        let height = (Int(size.height * scale) / 2) * 2
        guard width >= 640, height >= 480 else { return }
        stagePixels = CGSize(width: width, height: height)
    }

    /// "850 Kbps", "11.9 Mbps".
    private static func rate(_ bits: Int) -> String {
        bits >= 1_000_000
            ? String(format: String(localized: "%.1f Mbps", bundle: .module), Double(bits) / 1_000_000)
            : String(localized: "\(max(bits / 1000, 0)) Kbps", bundle: .module)
    }

    private var qualityMenu: some View {
        Menu {
            qualityChoices
        } label: {
            Label(.init("Quality", bundle: .module), systemImage: "slider.horizontal.3").stageControl()
        }
        .help(.init("Frame rate and image quality", bundle: .module))
    }

    /// The official viewer's 画质 choices, as pickers: each shows its
    /// choice checked, and choosing one keeps the others.
    @ViewBuilder private var qualityChoices: some View {
            Section(.init("Frame Rate", bundle: .module)) {
                Picker(.init("Frame Rate", bundle: .module), selection: streamBinding(\.fps)) {
                    ForEach(RemoteDesktopStreamSettings.frameRates, id: \.self) { fps in
                        Text("\(fps) fps", bundle: .module).tag(fps)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section(.init("Quality", bundle: .module)) {
                Picker(.init("Quality", bundle: .module), selection: streamBinding(\.quality)) {
                    ForEach(RemoteDesktopStreamSettings.qualities, id: \.value) { preset in
                        Text(preset.title).tag(preset.value)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                Toggle(.init("True Colour (4:4:4)", bundle: .module), isOn: streamBinding(\.trueColor))
            }
            // Locked, the host is still connected and takes the settings.
            if session.phase != .connected, session.phase != .authenticating {
                Section {
                    Text("Applies when connected", bundle: .module)
                }
            }
    }

    /// One field of the session's stream settings, the rest kept.
    private func streamBinding<Value>(_ field: WritableKeyPath<RemoteDesktopStreamSettings, Value>) -> Binding<Value> {
        Binding(
            get: { session.streamSettings[keyPath: field] },
            set: { value in
                var settings = session.streamSettings
                settings[keyPath: field] = value
                session.setStreamSettings(settings)
            }
        )
    }

    private var specialKeysMenu: some View {
        Menu {
            Button(.init("Esc", bundle: .module)) { send(RemoteDesktopSpecialKeys.click(RemoteDesktopSpecialKeys.escape)) }
            Button(.init("Tab", bundle: .module)) { send(RemoteDesktopSpecialKeys.click(RemoteDesktopSpecialKeys.tab)) }
            Button(.init("Return", bundle: .module)) { send(RemoteDesktopSpecialKeys.click(RemoteDesktopSpecialKeys.return)) }
            Button(.init("Delete ⌦", bundle: .module)) { send(RemoteDesktopSpecialKeys.click(RemoteDesktopSpecialKeys.deleteForward)) }
            Divider()
            Button(.init("Ctrl+Alt+Del", bundle: .module)) { send(RemoteDesktopSpecialKeys.ctrlAltDelete) }
            Button(.init("Alt+Tab", bundle: .module)) {
                send(RemoteDesktopSpecialKeys.combo(
                    [RemoteDesktopSpecialKeys.alt],
                    RemoteDesktopSpecialKeys.tab
                ))
            }
            Button(.init("Win / Super", bundle: .module)) { send(RemoteDesktopSpecialKeys.click(RemoteDesktopSpecialKeys.super)) }
            Divider()
            Menu(.init("Function Keys", bundle: .module)) {
                ForEach(1 ... 12, id: \.self) { n in
                    Button(.init("F\(n)", bundle: .module)) {
                        send(RemoteDesktopSpecialKeys.click(RemoteDesktopSpecialKeys.functionKey(n)))
                    }
                }
            }
            Menu(.init("Navigation", bundle: .module)) {
                Button(.init("Home", bundle: .module)) { send(RemoteDesktopSpecialKeys.click(RemoteDesktopSpecialKeys.home)) }
                Button(.init("End", bundle: .module)) { send(RemoteDesktopSpecialKeys.click(RemoteDesktopSpecialKeys.end)) }
                Button(.init("Page Up", bundle: .module)) { send(RemoteDesktopSpecialKeys.click(RemoteDesktopSpecialKeys.pageUp)) }
                Button(.init("Page Down", bundle: .module)) { send(RemoteDesktopSpecialKeys.click(RemoteDesktopSpecialKeys.pageDown)) }
                Button(.init("Insert", bundle: .module)) { send(RemoteDesktopSpecialKeys.click(RemoteDesktopSpecialKeys.insert)) }
                Button(.init("Backspace", bundle: .module)) { send(RemoteDesktopSpecialKeys.click(RemoteDesktopSpecialKeys.backspace)) }
            }
        } label: {
            Label(.init("Keys", bundle: .module), systemImage: "command").stageControl()
        }
        .help(.init("Send a special key the local keyboard can not reach", bundle: .module))
    }

    private func send(_ strokes: [RemoteDesktopKeyStroke]) {
        session.sendKeys(strokes)
    }

    private var viewOnlyButton: some View {
        Button { session.viewOnly.toggle() } label: {
            Label(session.viewOnly ? LocalizedStringResource("View Only", bundle: .module) : LocalizedStringResource("Control", bundle: .module), systemImage: session.viewOnly ? "eye" : "cursorarrow.motionlines").stageControl()
                .foregroundStyle(session.viewOnly ? Color.rxAccent : Color.rxInk)
        }
        .help(session.viewOnly ? LocalizedStringResource("View only: input stays local. Click to take control", bundle: .module) : LocalizedStringResource("Watch without sending mouse or keys", bundle: .module))
    }

    #if os(iOS) && !targetEnvironment(macCatalyst)
        /// Trackpad (the pointer moves as far as the finger) or direct touch
        /// (the pointer goes under it). A pencil, mouse or trackpad always
        /// points where it is.
        private var touchModeMenu: some View {
            Menu {
                Section {
                    ForEach(RemoteDesktopTouchMode.allCases, id: \.self) { mode in
                        Button {
                            touchMode = mode
                        } label: {
                            if mode == touchMode {
                                Label(mode.title, systemImage: "checkmark")
                            } else {
                                Text(mode.title)
                            }
                        }
                    }
                }
                Section {
                    switch touchMode {
                    case .trackpad:
                        Text("Drag to move the pointer, tap to click, hold then drag to drag", bundle: .module)
                    case .direct:
                        Text("Tap to click there, drag to drag, hold to right-click", bundle: .module)
                    }
                    Text("Two fingers: tap to right-click, drag to scroll, pinch to zoom", bundle: .module)
                    Text("Three fingers: tap for the keyboard", bundle: .module)
                }
            } label: {
                Label(touchMode.title, systemImage: touchMode.systemImage).stageControl()
            }
            .help(.init("How a finger moves the pointer", bundle: .module))
        }
    #endif

    private var clipboardMenu: some View {
        Menu {
            Button {
                let text = RemoteDesktopClipboard.read() ?? ""
                guard !text.isEmpty else {
                    flash(String(localized: "Pasteboard is empty", bundle: .module))
                    return
                }
                session.pushClipboard(text)
                flash(String(localized: "Sent \(text.count) characters to the remote clipboard", bundle: .module))
            } label: {
                Label(.init("Push local clipboard", bundle: .module), systemImage: "doc.on.clipboard")
            }
            Button {
                let text = session.remoteClipboard
                guard !text.isEmpty else {
                    flash(String(localized: "Remote clipboard is empty", bundle: .module))
                    return
                }
                RemoteDesktopClipboard.write(text)
                flash(String(localized: "Copied \(text.count) characters from the remote clipboard", bundle: .module))
            } label: {
                Label(.init("Pull remote clipboard", bundle: .module), systemImage: "clipboard")
            }
        } label: {
            Label(.init("Clipboard", bundle: .module), systemImage: "clipboard").stageControl()
        }
        .help(.init("The clipboard syncs itself while connected; these push and pull by hand", bundle: .module))
    }

    private var officialAppMenu: some View {
        Menu {
            officialAppChoices
        } label: {
            Label(.init("Official App", bundle: .module), systemImage: "pip").stageControl()
        }
        .help(.init("Hand off to the official UU Remote app", bundle: .module))
    }

    @ViewBuilder private var officialAppChoices: some View {
            #if os(macOS)
            // Mac Catalyst cannot exec uuyc-cli; the official app is opened
            // through its URL scheme or the CLI when it exists.
            if UULocalBridge.cliInstalled || UULocalBridge.officialAppInstalled {
                Button(.init("Open in UU Remote app", bundle: .module)) {
                    UULocalBridge.openControlInOfficialApp(for: session.machine)
                }
                if UULocalBridge.cliInstalled {
                    Button(.init("Open remote terminal (uuyc-cli)", bundle: .module)) {
                        try? UULocalBridge.cliTerminal(deviceID: session.machine.uuDeviceID)
                    }
                }
            } else {
                Text("UURemote.app is not installed", bundle: .module)
            }
            #else
            if officialAppInstalled {
                Button(.init("Open in UU Remote app (PiP)", bundle: .module)) {
                    UULocalBridge.openControlInOfficialApp(for: session.machine)
                }
                Button(.init("Re-authorize this device", bundle: .module)) {
                    UULocalBridge.openAuthorizeInOfficialApp(for: session.machine)
                }
            } else {
                Text("UURemote app is not installed", bundle: .module)
            }
            #endif
    }

    private var connectButton: some View {
        Group {
            if session.phase.isTerminal || session.phase == .idle {
                Button { session.connect() } label: {
                    Label(.init("Connect", bundle: .module), systemImage: "play.circle").stageControl()
                }
                .help(.init("Connect", bundle: .module))
            } else {
                Button { session.disconnect() } label: {
                    Label(.init("Disconnect", bundle: .module), systemImage: "stop.circle").stageControl()
                }
                .help(.init("Disconnect", bundle: .module))
            }
        }
    }

    private var textInputPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Type text on the remote host", bundle: .module)
                .font(.rxCaption)
                .foregroundStyle(Color.rxInkSecondary)
            HStack {
                TextField(String(localized: "Text to send", bundle: .module), text: $textDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 220)
                    .onSubmit { sendDraft() }
                Button(.init("Send", bundle: .module)) { sendDraft() }
                    .disabled(textDraft.isEmpty)
            }
        }
        .padding(12)
    }

    private func sendDraft() {
        guard !textDraft.isEmpty else { return }
        session.typeText(textDraft)
        textDraft = ""
        showsTextInput = false
    }

    private func flash(_ message: String, for seconds: Double = 2) {
        withAnimation { toast = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            withAnimation {
                if toast == message { toast = nil }
            }
        }
    }
}

private extension Label {
    /// A control of the stage's bar. On the Mac only its symbol, named by its
    /// tooltip; a touch screen has no tooltips, so there its name is written
    /// under the symbol, in a target at least 44 points high.
    func stageControl() -> some View {
        #if os(iOS) && !targetEnvironment(macCatalyst)
            labelStyle(StageControlLabelStyle())
        #else
            labelStyle(.iconOnly)
        #endif
    }
}

#if os(iOS) && !targetEnvironment(macCatalyst)
    /// Symbol over its name.
    private struct StageControlLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            VStack(spacing: 3) {
                configuration.icon
                    .font(.system(size: 18))
                    .frame(height: 22)
                configuration.title
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(minWidth: 52, minHeight: 44)
            .contentShape(Rectangle())
        }
    }
#endif
