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
        let short = info?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = info?["CFBundleVersion"] as? String ?? "Unknown"
        #if DEBUG
            return "Version: \(short) Build: \(build) Debug"
        #else
            return "Version: \(short) Build: \(build)"
        #endif
    }
}

/// The backdrop of Home: a soft glow in the accent colours and a few dots that
/// drift out from the middle, fading in and out. The dots are drawn in one
/// Canvas at most 30 times a second, and stop while the page is off screen,
/// the window is in the background or Reduce Motion is on; the glow is still.
public struct RXStarfield: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    #if os(macOS)
        @Environment(\.controlActiveState) private var controlActiveState
    #else
        @Environment(\.scenePhase) private var scenePhase
    #endif
    @State private var onScreen = false
    @State private var stars = Star.make(count: 18)

    public init() {}

    public var body: some View {
        ZStack {
            glow
            if !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { timeline in
                    Canvas { context, size in
                        draw(in: &context, size: size, at: timeline.date.timeIntervalSinceReferenceDate)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
    }

    private var paused: Bool {
        #if os(macOS)
            return !onScreen || controlActiveState == .inactive
        #else
            return !onScreen || scenePhase != .active
        #endif
    }

    /// Three wide radial washes, still; light enough for text to sit on.
    private var glow: some View {
        let strength = colorScheme == .dark ? 0.30 : 0.20
        return GeometryReader { proxy in
            let side = max(proxy.size.width, proxy.size.height)
            ZStack {
                wash(Color.rxAccent, strength, side * 0.55)
                    .position(x: proxy.size.width * 0.30, y: proxy.size.height * 0.30)
                wash(Color.rxSeries2, strength * 0.8, side * 0.50)
                    .position(x: proxy.size.width * 0.75, y: proxy.size.height * 0.62)
                wash(Color(red: 0.93, green: 0.55, blue: 0.78), strength * 0.6, side * 0.40)
                    .position(x: proxy.size.width * 0.40, y: proxy.size.height * 0.85)
            }
        }
    }

    private func wash(_ color: Color, _ opacity: Double, _ radius: CGFloat) -> some View {
        RadialGradient(
            colors: [color.opacity(opacity), color.opacity(0)],
            center: .center,
            startRadius: 0,
            endRadius: radius
        )
        .frame(width: radius * 2, height: radius * 2)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, at time: TimeInterval) {
        let center = CGPoint(x: size.width / 2, y: size.height * 0.42)
        let reach = hypot(size.width, size.height) * 0.5
        // The whole field sways a little, as the original's did.
        let sway = CGSize(width: sin(time / 7) * 14, height: cos(time / 9) * 10)
        let color = Color.rxAccent
        for star in stars {
            let progress = ((time + star.phase) / star.period).truncatingRemainder(dividingBy: 1)
            let distance = 40 + progress * reach * star.reach
            let point = CGPoint(
                x: center.x + cos(star.angle) * distance + sway.width,
                y: center.y + sin(star.angle) * distance + sway.height
            )
            let diameter = star.size * (1 + progress * 0.8)
            let rect = CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2, width: diameter, height: diameter)
            context.opacity = sin(progress * .pi) * star.opacity
            context.fill(Path(ellipseIn: rect), with: .color(color))
        }
    }

    private struct Star {
        let angle: Double
        let period: Double
        let phase: Double
        let reach: Double
        let size: Double
        let opacity: Double

        static func make(count: Int) -> [Star] {
            (0 ..< count).map { _ in
                Star(
                    angle: .random(in: 0 ..< 2 * .pi),
                    period: .random(in: 14 ... 22),
                    phase: .random(in: 0 ..< 22),
                    reach: .random(in: 0.7 ... 1.0),
                    size: .random(in: 4 ... 7),
                    opacity: .random(in: 0.45 ... 0.8)
                )
            }
        }
    }
}
