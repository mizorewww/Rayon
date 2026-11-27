//
//  DiagnosticsSettings.swift
//  Rayon
//
//  Settings › About › Diagnostics & Usage, the sheet that shows what is
//  sent, the bundled privacy policy and the one-time notice on Home. Shared
//  by both platforms; docs/telemetry.md §4.6 is the design.
//

import RayonModule
import SwiftUI

/// The level slider and what it means, on this device only.
struct DiagnosticsSettings: View {
    @State private var showsReports = false
    @State private var showsPolicy = false

    private var telemetry: Telemetry {
        .shared
    }

    var body: some View {
        let level = telemetry.level
        LabeledContent {
            Slider(
                value: Binding(
                    get: { Double(telemetry.level.rawValue) },
                    set: { value in
                        let chosen = TelemetryLevel(rawValue: Int(value.rounded())) ?? .off
                        if chosen != telemetry.choice { telemetry.setLevel(chosen) }
                    }
                ),
                in: 0 ... 3,
                step: 1
            ) {
                Text("Diagnostics & Usage")
            } minimumValueLabel: {
                Text("Off")
            } maximumValueLabel: {
                Text("Detailed")
            }
            .labelsHidden()
            .accessibilityValue(level.title)
            .frame(minWidth: 180, maxWidth: 260)
        } label: {
            Text(level.title)
            Text("\(level.summary) This setting applies to this device only.")
        }
        LabeledContent {
            HStack {
                Button("Privacy Policy") { showsPolicy = true }
                Button("View What's Sent…") { showsReports = true }
            }
            #if os(iOS)
            // A form row taps every plain button in it at once.
            .buttonStyle(.borderless)
            #endif
        } label: {
            Text("Privacy")
            Text("Never sent: server addresses, usernames, keys, commands, files or terminal content.")
        }
        .sheet(isPresented: $showsReports) { TelemetryReportsSheet() }
        .sheet(isPresented: $showsPolicy) { PrivacyPolicySheet() }
    }
}

/// The pending reports and the last one sent, exactly as they go out.
struct TelemetryReportsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pending: [TelemetryReport] = []
    @State private var lastSent: TelemetryReport?

    private var json: String {
        Telemetry.json(pending + (lastSent.map { [$0] } ?? []))
    }

    var body: some View {
        SheetScaffold(
            "What's Sent",
            lead: "\(pending.count) report\(pending.count == 1 ? "" : "s") waiting\(lastSent == nil ? "" : ", then the last one sent"). \(Telemetry.sendingAllowed ? "" : "This build does not send them.")"
        ) {
            ScrollView {
                Text(json)
                    .font(.rxCode)
                    .foregroundStyle(.rxInkSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(RX.Space.s4)
            }
            .frame(minHeight: 280, maxHeight: 420)
            .clipShape(RoundedRectangle(cornerRadius: RX.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: RX.Radius.lg, style: .continuous)
                    .strokeBorder(Color.rxHairline, lineWidth: 1)
            )
        } footer: {
            ShareLink(item: json, preview: SharePreview("Rayon telemetry reports"))
                .buttonStyle(.rx)
                .fixedSize()
            Button("Delete Pending Reports", role: .destructive) {
                Task {
                    await Telemetry.shared.deletePendingReports()
                    await load()
                }
            }
            .buttonStyle(.rx)
            .fixedSize()
            .disabled(pending.isEmpty)
            Button("Reset Activity History") {
                Task { await Telemetry.shared.resetActivityHistory() }
            }
            .buttonStyle(.rx)
            .fixedSize()
            .help("Forget the days Rayon was used, which only leave this device as a count.")
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.rxPrimary)
                .keyboardShortcut(.defaultAction)
        }
        #if os(macOS)
        .frame(width: 680)
        #endif
        .task { await load() }
    }

    private func load() async {
        pending = await Telemetry.shared.pendingReports()
        lastSent = await Telemetry.shared.lastSentReport()
    }
}

/// The privacy policy bundled per language, shown in the app as FlowDown
/// shows its own. The files are not in .lproj folders: those would mark the
/// app as localized and turn the system's menus Chinese around English rows.
struct PrivacyPolicySheet: View {
    @Environment(\.dismiss) private var dismiss

    static var text: AttributedString {
        let language = Bundle.preferredLocalizations(from: ["en", "zh-Hans", "zh-Hant"], forPreferences: Locale.preferredLanguages).first ?? "en"
        guard let url = Bundle.main.url(forResource: "PrivacyPolicy-\(language)", withExtension: "md", subdirectory: "Privacy"),
              let markdown = try? String(contentsOf: url, encoding: .utf8)
        else { return AttributedString("The privacy policy could not be loaded.") }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
    }

    var body: some View {
        SheetScaffold("Privacy Policy") {
            ScrollView {
                Text(Self.text)
                    .font(.rxBody)
                    .foregroundStyle(.rxInkSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(RX.Space.s4)
            }
            .frame(minHeight: 320, maxHeight: 480)
            .clipShape(RoundedRectangle(cornerRadius: RX.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: RX.Radius.lg, style: .continuous)
                    .strokeBorder(Color.rxHairline, lineWidth: 1)
            )
        } footer: {
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.rxPrimary)
                .keyboardShortcut(.defaultAction)
        }
        #if os(macOS)
        .frame(width: 600)
        #endif
    }
}

/// Shown once, inline on Home: never a sheet that blocks work, never again
/// once answered. In the EEA, the UK and Switzerland nothing is sent until a
/// choice, and closing the card is "Don't Share".
struct TelemetryNoticeCard: View {
    @State private var showsSettings = false
    @State private var showsPolicy = false

    private var telemetry: Telemetry {
        .shared
    }

    var body: some View {
        Group {
            if telemetry.showsNotice {
                card
            }
        }
        .sheet(isPresented: $showsPolicy) { PrivacyPolicySheet() }
        #if os(iOS)
            .sheet(isPresented: $showsSettings) {
                SheetScaffold("Diagnostics & Usage") {
                    Form { DiagnosticsSettings() }
                } footer: {
                    Spacer()
                    Button("Done") {
                        telemetry.markNoticeShown()
                        showsSettings = false
                    }
                    .buttonStyle(.rxPrimary)
                }
                .presentationDetents([.medium])
            }
        #endif
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: RX.Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                Label("Diagnostics & Usage", systemImage: "chart.bar.doc.horizontal")
                    .font(.rxBody.weight(.semibold))
                    .foregroundStyle(.rxInk)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(telemetry.asksForConsent ? "Don't Share" : "OK")
            }
            Text("Rayon sends anonymous crash reports and feature counts to help fix bugs. It never sends your servers, usernames or terminal content.")
                .font(.rxBody)
                .foregroundStyle(.rxInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if telemetry.region == .china {
                Button("Read the Privacy Policy") { showsPolicy = true }
                    .buttonStyle(.borderless)
            }
            HStack(spacing: RX.Space.s2) {
                if telemetry.asksForConsent {
                    Button("Share Anonymous Data") { telemetry.setLevel(.usage) }
                        .buttonStyle(.rx)
                    Button("Don't Share") { telemetry.setLevel(.off) }
                        .buttonStyle(.rx)
                } else {
                    Spacer()
                    Button("Settings…") { openSettings() }
                        .buttonStyle(.rx)
                    Button("OK") { telemetry.markNoticeShown() }
                        .buttonStyle(.rxPrimary)
                }
            }
        }
        .frame(maxWidth: 460)
        .rxCard()
    }

    private func dismiss() {
        if telemetry.asksForConsent {
            telemetry.setLevel(.off)
        } else {
            telemetry.markNoticeShown()
        }
    }

    private func openSettings() {
        #if os(macOS)
            telemetry.markNoticeShown()
            AppRouter.shared.openSettings(SettingsCategory.about)
        #else
            showsSettings = true
        #endif
    }
}
