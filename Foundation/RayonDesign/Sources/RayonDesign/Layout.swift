//
//  Layout.swift
//  RayonDesign
//

import SwiftUI

#if os(macOS)
    import AppKit

    /// The translucent window backdrop: the desktop shows through, blurred.
    public struct RXWindowBackground: NSViewRepresentable {
        public init() {}

        public func makeNSView(context _: Context) -> NSVisualEffectView {
            let view = NSVisualEffectView()
            view.material = .underWindowBackground
            view.blendingMode = .behindWindow
            view.state = .followsWindowActiveState
            return view
        }

        public func updateNSView(_: NSVisualEffectView, context _: Context) {}
    }

#endif

/// Wraps children onto new lines (toggle chips, tags).
public struct RXFlowLayout: Layout {
    let spacing: CGFloat
    let alignment: HorizontalAlignment

    public init(spacing: CGFloat = 6, alignment: HorizontalAlignment = .leading) {
        self.spacing = spacing
        self.alignment = alignment
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x: CGFloat
            switch alignment {
            case .trailing: x = bounds.maxX - row.width
            case .center: x = bounds.minX + (bounds.width - row.width) / 2
            default: x = bounds.minX
            }
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

// MARK: - Lists

public extension View {
    /// Inset-grouped lists on `window`, rows on `surface` cards, `accent` tint.
    func rxGroupedList() -> some View {
        scrollContentBackground(.hidden)
            .background(RXBackdrop().ignoresSafeArea())
            .tint(.rxAccent)
    }

    /// A list row on a frosted `surface`.
    func rxListRow() -> some View {
        listRowBackground(Rectangle().fill(.regularMaterial))
    }
}

/// Caps section header for grouped lists.
public struct RXSectionHeader: View {
    let title: LocalizedStringResource
    public init(_ title: LocalizedStringResource) { self.title = title }
    public var body: some View {
        CapsLabel(title)
            .textCase(nil)
    }
}

/// The page backdrop: the translucent window on the Mac; on iOS, where the desktop
/// cannot show through, a soft tinted gradient that the frosted cards blur.
public struct RXBackdrop: View {
    public init() {}

    public var body: some View {
        #if os(macOS)
            RXWindowBackground()
        #else
            ZStack {
                Color.rxWindow
                LinearGradient(
                    colors: [Color.rxAccent.opacity(0.10), .clear, Color.rxSeries2.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        #endif
    }
}
