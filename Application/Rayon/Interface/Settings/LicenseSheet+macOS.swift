//
//  LicenseSheet+macOS.swift
//  Rayon
//
//  The license and the agreement, from Settings › About and at first launch.
//

#if os(macOS)
    import AppKit
    import RayonModule
    import SwiftUI

    enum AboutDocument: String, Identifiable {
        case license = "LICENSE"
        case agreement = "EULA"

        var id: String {
            rawValue
        }

        var title: LocalizedStringResource {
            switch self {
            case .license: "License"
            case .agreement: "End User License Agreement"
            }
        }

        var text: String {
            guard let url = Bundle.main.url(forResource: rawValue, withExtension: nil),
                  let string = try? String(contentsOf: url, encoding: .utf8)
            else { return String(localized: "The text could not be loaded.") }
            return string
        }
    }

    struct LicenseSheet: View {
        let document: AboutDocument
        let close: () -> Void

        var body: some View {
            SheetScaffold(document.title) {
                ScrollView {
                    Text(document.text)
                        .font(.system(size: 12))
                        .foregroundStyle(.rxInkSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(RX.Space.s4)
                }
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: RX.Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: RX.Radius.lg, style: .continuous)
                        .strokeBorder(Color.rxHairline, lineWidth: 1)
                )
            } footer: {
                Spacer()
                Button("Done", action: close)
                    .buttonStyle(.rxPrimary)
                    .keyboardShortcut(.defaultAction)
            }
            .frame(width: 600)
        }
    }

    /// First launch: the license in a scroll card, the agree checkbox, Quit and Continue.
    struct AgreementSheet: View {
        @Environment(\.dismiss) private var dismiss
        @State private var agreed = false

        var body: some View {
            SheetScaffold("Welcome to Rayon") {
                VStack(alignment: .leading, spacing: RX.Space.s3) {
                    ScrollView {
                        Text(AboutDocument.agreement.text)
                            .font(.system(size: 12))
                            .foregroundStyle(.rxInkSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(RX.Space.s4)
                    }
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: RX.Radius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: RX.Radius.lg, style: .continuous)
                            .strokeBorder(Color.rxHairline, lineWidth: 1)
                    )
                    Toggle("I have read and agree to the license", isOn: $agreed)
                        .rxCheckboxToggle()
                        .font(.rxBody)
                }
            } footer: {
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.rx)
                Spacer()
                Button("Continue") {
                    RayonStore.shared.licenseAgreed = true
                    dismiss()
                }
                .buttonStyle(.rxPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(!agreed)
            }
            .frame(width: 560)
            .interactiveDismissDisabled()
        }
    }
#endif
