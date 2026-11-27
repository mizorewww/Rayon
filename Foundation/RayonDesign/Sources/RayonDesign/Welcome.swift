//
//  Welcome.swift
//  RayonDesign
//
//  What Home is made of on both platforms, as the first Rayon had it: the app
//  icon, the version line, and a soft glow with dots drifting out from the
//  middle behind Quick Connect.
//

import SwiftUI

/// The app icon, drawn from the "RayonIcon" image of the app's asset catalog
/// (the artwork of Rayon.icon on white) in the rounded square of an app icon.
public struct RXAppIcon: View {
    let size: CGFloat

    public init(size: CGFloat = 128) {
        self.size = size
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
        Image("RayonIcon")
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.14), radius: size * 0.08, y: size * 0.03)
            .accessibilityHidden(true)
    }
}

public enum RXAppVersion {
    /// "Version: 1.3 Build: 4", the line at the foot of Home.
    public static var text: String {
        let info = Bundle.main.infoDictionary
        let unknown = String(localized: "Unknown", bundle: .module)
        let short = info?["CFBundleShortVersionString"] as? String ?? unknown
        let build = info?["CFBundleVersion"] as? String ?? unknown
        let version = String(localized: "Version: \(short) Build: \(build)", bundle: .module)
        #if DEBUG
            return version + " Debug"
        #else
            return version
        #endif
    }
}
