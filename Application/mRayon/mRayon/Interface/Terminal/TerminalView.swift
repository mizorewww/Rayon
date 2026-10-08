//
//  TerminalView.swift
//  mRayon
//
//  Created by Lakr Aream on 2022/3/2.
//

import RayonModule
import SwiftUI
import XTerminalUI

struct TerminalView: View {
    @StateObject var context: TerminalContext

    @State var interfaceToken = UUID()

    @State var terminalSize: CGSize = TerminalContext.defaultTerminalSize

    @State var openControlKeyPopover: Bool = false
    @State var controlKey: String = ""

    @StateObject var store = RayonStore.shared

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if context.interfaceToken == interfaceToken {
                GeometryReader { r in
                    VStack(spacing: 0) {
                        context.termInterface
                            .onChange(of: r.size) { _ in
                                guard context.interfaceToken == interfaceToken else {
                                    debugPrint("interface token mismatch")
                                    return
                                }
                                updateTerminalSize()
                            }
                            .onAppear {
                                context.termInterface.setTerminalFontSize(with: store.terminalFontSize)
                            }
                            .onChange(of: store.terminalFontSize) { newValue in
                                context.termInterface.setTerminalFontSize(with: newValue)
                            }
                            .padding(r.size.width > 600 ? 8 : 2)
                            .background(Color.rxTerminalBackground)
                        if !context.destroyedSession {
                            buttonGroup
                        }
                    }
                }
            } else {
                EmptyStateView(
                    "Terminal moved to another window",
                    systemImage: "macwindow",
                    message: "This session is open in another window."
                )
            }
        }
        .background(Color.rxTerminalBackground.ignoresSafeArea())
        .disabled(context.destroyedSession)
        .onAppear {
            debugPrint("set interface token \(interfaceToken)")
            context.interfaceToken = interfaceToken
        }
        .navigationTitle(context.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The key bar above the keyboard: esc, tab, ctrl, arrows, paste.
    var buttonGroup: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if context.closed {
                    keyButton(systemImage: "arrow.clockwise", label: "Reconnect", disableWhenClosed: false) {
                        DispatchQueue.global().async {
                            context.putInformation("[i] Reconnecting with the details from when this session started.")
                            context.putInformation("    If the server was edited, open a new terminal instead.")
                            context.processBootstrap()
                        }
                    }
                }
                keyButton(text: "esc") { safeWriteBase64("Gw==") }
                keyButton(text: "tab") { safeWriteBase64("CQ==") }
                keyButton(text: "ctrl") { openControlKeyPopover = true }
                    .popover(isPresented: $openControlKeyPopover) {
                        HStack(spacing: RX.Space.s2) {
                            Text("ctrl +")
                                .font(.rxCode)
                            TextField("Key", text: $controlKey)
                                .textInputAutocapitalization(.characters)
                                .disableAutocorrection(true)
                                .frame(width: 48)
                                .onChange(of: controlKey) { newValue in
                                    guard let f = newValue.uppercased().last else {
                                        if !controlKey.isEmpty { controlKey = "" }
                                        return
                                    }
                                    if controlKey != String(f) {
                                        controlKey = String(f)
                                    }
                                }
                                .onSubmit { sendCtrl() }
                            Button("Send") { sendCtrl() }
                                .buttonStyle(.rxPrimary)
                        }
                        .padding()
                        .modifier(CompactPopover())
                    }
                Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 20)
                keyButton(systemImage: "arrow.left", label: "Left") { safeWriteBase64("G1tE") }
                keyButton(systemImage: "arrow.up", label: "Up") { safeWriteBase64("G1tB") }
                keyButton(systemImage: "arrow.down", label: "Down") { safeWriteBase64("G1tC") }
                keyButton(systemImage: "arrow.right", label: "Right") { safeWriteBase64("G1tD") }
                Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 20)
                keyButton(systemImage: "doc.on.clipboard", label: "Paste") {
                    guard let str = UIPasteboard.general.string else {
                        UIBridge.presentError(with: "Empty Pasteboard")
                        return
                    }
                    UIBridge.requiresConfirmation(
                        message: "Paste into the terminal?",
                        informative: str.count > 200 ? String(str.prefix(200)) + "…" : str,
                        confirmTitle: "Paste",
                        destructive: false
                    ) { yes in
                        if yes { self.safeWrite(str) }
                    }
                }
                keyButton(systemImage: "xmark", label: "Close Session", disableWhenClosed: false) {
                    if context.closed {
                        dismiss()
                        TerminalManager.shared.end(for: context.id)
                    } else {
                        UIBridge.requiresConfirmation(
                            message: "Close this session?",
                            informative: "Anything running in it is stopped.",
                            confirmTitle: "Close Session"
                        ) { yes in
                            if yes { context.processShutdown() }
                        }
                    }
                }
            }
            .padding(.horizontal, RX.Space.s3)
            .padding(.vertical, RX.Space.s2)
        }
        .background(Color.rxTerminalBackground)
    }

    func sendCtrl() {
        let key = controlKey
        controlKey = ""
        openControlKeyPopover = false
        /*
         Note: The Ctrl-Key representation is simply associating the non-printable characters from ASCII code 1 with the printable (letter) characters from ASCII code 65 ("A"). ASCII code 1 would be ^A (Ctrl-A), while ASCII code 7 (BEL) would be ^G (Ctrl-G). This is a common representation (and input method) and historically comes from one of the VT series of terminals.

         https://gist.github.com/fnky/458719343aabd01cfb17a3a4f7296797
         */
        guard key.count == 1 else { return }
        let char = Character(key)
        guard let asciiValue = char.asciiValue,
              let asciiInt = Int(exactly: asciiValue) // 65 = "A" 1 = "CTRL+A"
        else {
            debugPrint("failed to encode control")
            return
        }
        let ctrlInt = asciiInt - 64
        guard ctrlInt > 0, ctrlInt < 65 else {
            debugPrint("control character overflow")
            return
        }
        guard let us = UnicodeScalar(ctrlInt) else {
            debugPrint("failed to encode control")
            return
        }
        let nc = Character(us)
        let st = String(nc)
        safeWrite(st)
    }

    func safeWriteBase64(_ base64: String) {
        guard let data = Data(base64Encoded: base64),
              let str = String(data: data, encoding: .utf8)
        else {
            debugPrint("failed to decode \(base64)")
            return
        }
        safeWrite(str)
    }

    func safeWrite(_ str: String) {
        guard !context.closed else {
            return
        }
        guard context.interfaceToken == interfaceToken else {
            return
        }
        context.insertBuffer(str)
    }

    func keyButton(
        text: String? = nil,
        systemImage: String? = nil,
        label: String? = nil,
        disableWhenClosed: Bool = true,
        block: @escaping () -> Void
    ) -> some View {
        Button {
            if context.closed, disableWhenClosed { return }
            block()
        } label: {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .medium))
                } else {
                    Text(text ?? "")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                }
            }
            .foregroundStyle(.rxTerminalForeground)
            .frame(minWidth: 40, minHeight: 34)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label ?? text ?? "")
        .disabled(disableWhenClosed && context.interfaceDisabled)
        .opacity(disableWhenClosed && context.interfaceDisabled ? 0.4 : 1)
    }

    func updateTerminalSize() {
        let core = context.termInterface
        let origSize = terminalSize
        DispatchQueue.global().async {
            let newSize = core.requestTerminalSize()
            guard newSize.width > 5, newSize.height > 5 else {
                debugPrint("ignoring malformed terminal size: \(newSize)")
                return
            }
            if newSize != origSize {
                onMainThread {
                    guard context.interfaceToken == interfaceToken else {
                        debugPrint("interface token mismatch")
                        return
                    }
                    debugPrint("new terminal size: \(newSize)")
                    terminalSize = newSize
                    context.shell.explicitRequestStatusPickup()
                }
            }
        }
    }
}

/// Keeps the ctrl popover a popover on iPhone.
private struct CompactPopover: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.presentationCompactAdaptation(.popover)
        } else {
            content
        }
    }
}
