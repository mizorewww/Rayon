//
//  HomeBackdrop.swift
//  Rayon
//
//  The backdrop of Home, as Rayon has always had it: a soft glow in the
//  accent colours and a few dots that drift out from the middle, fading in
//  and out.
//

import RayonDesign
import SwiftUI

/// The glow is still. The dots are drawn in one Canvas at most 30 times a
/// second, and stop while the page is off screen, the window is in the
/// background, Reduce Motion is on or the device is in Low Power Mode.
struct HomeBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    #if os(macOS)
        @Environment(\.controlActiveState) private var controlActiveState
    #else
        @Environment(\.scenePhase) private var scenePhase
    #endif
    @State private var onScreen = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var stars = Star.make(count: 18)

    var body: some View {
        ZStack {
            glow
            if !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { timeline in
                    // Drawn off the main thread: drawn on it, the Canvas
                    // allocated and filled a window-sized surface there each
                    // time Home opened, while the page slid in.
                    Canvas(rendersAsynchronously: true) { context, size in
                        draw(in: &context, size: size, at: timeline.date.timeIntervalSinceReferenceDate)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .NSProcessInfoPowerStateDidChange) {
                lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }

    private var paused: Bool {
        #if os(macOS)
            let active = controlActiveState != .inactive
        #else
            let active = scenePhase == .active
        #endif
        return !onScreen || !active || lowPower
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
