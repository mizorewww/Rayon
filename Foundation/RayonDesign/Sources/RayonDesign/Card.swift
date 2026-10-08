//
//  Card.swift
//  RayonDesign
//

import SwiftUI

/// A card floating over the translucent window: a heavily blurred material with a
/// faint tint of `surface`, a soft shadow, and a light specular edge in dark mode.
struct RXCardBackground: View {
    var radius: CGFloat = RX.Radius.card
    var fill: Color = .rxSurface
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(.thickMaterial)
            .overlay(shape.fill(fill.opacity(colorScheme == .dark ? 0.35 : 0.55)))
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(colorScheme == .dark ? 0.12 : 0.6), Color.white.opacity(colorScheme == .dark ? 0.02 : 0.15)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.06), radius: 12, x: 0, y: 6)
    }
}

public extension View {
    /// Places the view on a `surface` card with `radius-card` and `shadow-card`.
    /// - Parameter padding: inner padding, `space-4` by default; pass 8 for flush lists.
    func rxCard(padding: CGFloat = RX.Space.s4) -> some View {
        self
            .padding(padding)
            .background(RXCardBackground())
    }

    /// Card chrome without inner padding, clipped to the card shape.
    func rxCardChrome(radius: CGFloat = RX.Radius.card) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .background(RXCardBackground(radius: radius))
    }
}

/// Uppercase `caption-caps` label in `ink-secondary`.
public struct CapsLabel: View {
    let text: String
    var color: Color = .rxInkSecondary

    public init(_ text: String, color: Color = .rxInkSecondary) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text.uppercased())
            .font(.rxCaption)
            .tracking(rxCapsTracking)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// A card's head row: caption on the left, at most one control on the right.
public struct CardHead<Trailing: View>: View {
    let title: String
    let trailing: Trailing

    public init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: RX.Space.s2) {
            CapsLabel(title)
            Spacer(minLength: RX.Space.s2)
            trailing
        }
        .frame(minHeight: RX.controlHeight)
    }
}

public extension CardHead where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

/// Small scale or source hint (`axis` style, `ink-tertiary`).
public struct HintText: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text)
            .font(.rxAxis)
            .foregroundStyle(.rxInkTertiary)
            .lineLimit(1)
    }
}

/// One-sentence help text (`ink-secondary`, 11pt); `danger` when `isError`.
public struct HelpText: View {
    let text: String
    let isError: Bool
    public init(_ text: String, isError: Bool = false) {
        self.text = text
        self.isError = isError
    }

    public var body: some View {
        Text(text)
            .font(.rxHelp)
            .foregroundStyle(isError ? Color.rxDanger : Color.rxInkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 1px `hairline` divider.
public struct Hairline: View {
    let vertical: Bool
    public init(vertical: Bool = false) { self.vertical = vertical }
    public var body: some View {
        Rectangle()
            .fill(Color.rxHairline)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

/// Key-cap hint such as `⌘↩`.
public struct KeyHint: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.rxInkSecondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.rxSurfaceSunken))
    }
}
