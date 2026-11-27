//
//  HomeBackdrop.swift
//  Rayon
//
//  The backdrop of Home: a soft wash of the accent colours drifting slowly,
//  light enough for text to sit on. ColorfulX draws it on the GPU, as
//  FlowDown's welcome page does; with Reduce Motion it holds still.
//

import ColorfulX
import RayonDesign
import SwiftUI

struct HomeBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let strength = colorScheme == .dark ? 0.30 : 0.20
        ColorfulView(
            color: [
                Color.rxAccent.opacity(strength),
                Color.rxSeries2.opacity(strength * 0.8),
                Color(red: 0.93, green: 0.55, blue: 0.78).opacity(strength * 0.6),
                .clear, .clear, .clear, .clear, .clear,
            ],
            speed: .constant(reduceMotion ? 0 : 0.5),
            frameLimit: .constant(30),
            renderScale: .constant(0.1),
            repeats: false
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
