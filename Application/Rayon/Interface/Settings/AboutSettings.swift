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
        LabeledContent {
            Link(destination: URL(string: "https://github.com/mizorewww/Rayon")!) {
                Label("GitHub", systemImage: "arrow.up.right.square")
            }
        } label: {
            Text("Source code")
            Text("mizorewww/Rayon on GitHub")
        }
        LabeledContent {
            Link(destination: URL(string: "https://github.com/mizorewww/Rayon/issues")!) {
                Label("Issues", systemImage: "arrow.up.right.square")
            }
        } label: {
            Text("Report a problem")
            Text("Bugs and ideas go to the project's issue tracker.")
        }
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
