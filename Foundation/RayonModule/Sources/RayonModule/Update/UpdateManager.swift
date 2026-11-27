//
//  UpdateManager.swift
//  RayonModule
//
//  The update check FlowDown's UpdateManager does: GitHub's latest release,
//  compared to the running version with DpkgVersion.
//

import DpkgVersion
import Foundation
import Logger

public struct GitHubRelease: Decodable, Equatable, Sendable {
    public let tagName: String
    public let htmlURL: URL
    public let draft: Bool
    public let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
    }
}

public enum DistributionChannel: Equatable, Sendable {
    /// The App Store and TestFlight, which update the app themselves.
    case fromApple
    /// The notarized disk image on GitHub releases.
    case fromGitHub

    public static var current: DistributionChannel {
        #if os(macOS)
            .fromGitHub
        #else
            .fromApple
        #endif
    }
}

public struct UpdateManager: Sendable {
    public struct RemotePackage: Equatable, Sendable {
        public let version: String
        public let downloadURL: URL
    }

    public static let shared = UpdateManager(
        channel: .current,
        currentVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
        latestRelease: {
            let url = URL(string: "https://api.github.com/repos/mizorewww/Rayon/releases/latest")!
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode(GitHubRelease.self, from: data)
        }
    )

    public let channel: DistributionChannel
    public let currentVersion: String
    let latestRelease: @Sendable () async throws -> GitHubRelease

    public var canCheckForUpdates: Bool {
        channel == .fromGitHub
    }

    /// The newer release, or nil when this build is current. Only contacts
    /// GitHub when called, so nothing runs unless the user asks.
    public func availableUpdate() async throws -> RemotePackage? {
        guard canCheckForUpdates else { return nil }
        Logger.app.infoFile("checking for updates from \(currentVersion)")
        let release = try await latestRelease()
        let package = Self.update(from: release, over: currentVersion)
        Logger.app.infoFile("latest release \(release.tagName); update: \(package?.version ?? "none")")
        return package
    }

    /// Release tags read `v2.8`; the bundle's short version reads `2.8`.
    /// The build number is not compared: tags do not carry it.
    static func update(from release: GitHubRelease, over currentVersion: String) -> RemotePackage? {
        guard !release.draft, !release.prerelease else { return nil }
        let version = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
        guard Version.compare(version, currentVersion) > 0 else { return nil }
        return RemotePackage(version: version, downloadURL: release.htmlURL)
    }
}
