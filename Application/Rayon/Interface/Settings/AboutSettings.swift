//
//  AboutSettings.swift
//  Rayon
//
//  Settings › About: the version, the source, the license, and who made it.
//

import RayonModule
import SwiftUI

struct AboutSettings: View {
    #if os(macOS)
        @State private var document: AboutDocument?
    #endif

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        #if DEBUG
            return "\(short) (\(build)) · Debug"
        #else
            return "\(short) (\(build))"
        #endif
    }

    /// The commit this copy was built from, written in at build time.
    private var commit: String {
        guard let url = Bundle.main.url(forResource: "BuildInfo", withExtension: "plist"),
              let info = NSDictionary(contentsOf: url),
              let commit = info["GitCommit"] as? String, !commit.isEmpty
        else { return "Unknown" }
        return commit
    }

    var body: some View {
        LabeledContent("Version") {
            Text(version)
                .monospacedDigit()
                .textSelection(.enabled)
        }
        LabeledContent {
            Text(commit)
                .font(.body.monospaced())
                .textSelection(.enabled)
        } label: {
            Text("Build")
            Text("The git commit this copy was built from; \"-dirty\" when the source had uncommitted changes.")
        }
        linkRow("Source code", "mizorewww/Rayon on GitHub", link: "GitHub", to: "https://github.com/mizorewww/Rayon")
        linkRow("Report a problem", "Bugs and ideas go to the project's issue tracker.", link: "Issues", to: "https://github.com/mizorewww/Rayon/issues")
        #if os(macOS)
            LabeledContent("Legal") {
                HStack {
                    Button("License…") { document = .license }
                    Button("Agreement…") { document = .agreement }
                        .help("End user license agreement")
                }
            }
            .sheet(item: $document) { item in
                LicenseSheet(document: item) { document = nil }
            }
        #else
            NavigationLink("License") { LicenseView() }
        #endif
    }

    /// A row that opens a web page. On iOS the whole row is the link: a
    /// LabeledContent holding a Link and its Label sized wrongly in a Form,
    /// leaving a blank gap and wrapping the link under its label.
    @ViewBuilder
    private func linkRow(_ title: String, _ detail: String, link: String, to address: String) -> some View {
        let url = URL(string: address)!
        #if os(macOS)
            LabeledContent {
                Link(destination: url) {
                    Label(link, systemImage: "arrow.up.right.square")
                }
            } label: {
                Text(title)
                Text(detail)
            }
        #else
            Link(destination: url) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .foregroundStyle(Color.primary)
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(Color.secondary)
                    }
                    Spacer()
                    // Text and an image, not a Label: a Label in a Form row
                    // drops its title and swells the row.
                    Text(link)
                    Image(systemName: "arrow.up.right.square")
                }
            }
        #endif
    }
}

struct AcknowledgementSettings: View {
    var body: some View {
        LabeledContent("Maintained by", value: "mizorewww")
        acknowledgement("Originally created by", "Lakr Aream (@Lakr233) with @__oquery, @zlind0, @unixzii, @82flex and @xnth97. This version is not affiliated with or endorsed by them.")
        #if os(macOS)
            acknowledgement("Terminal", "Ghostty, its configuration catalog and app icon presets (MIT, Ghostty contributors).")
        #else
            acknowledgement("Terminal", "Ghostty and its configuration catalog (MIT, Ghostty contributors).")
        #endif
        acknowledgement("Libraries", LicenseNotices.bundledLibraries.joined(separator: " · "))
    }

    private func acknowledgement(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}
