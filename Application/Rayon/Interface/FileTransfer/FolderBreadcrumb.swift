//
//  FolderBreadcrumb.swift
//  Rayon
//
//  The current remote folder: one clickable segment per folder, the last in
//  `ink` semibold. Long paths collapse middle segments into "…".
//

import SwiftUI

struct FolderBreadcrumb: View {
    let url: URL
    let navigate: (String) -> Void

    var body: some View {
        let components = url.pathComponents
        let indices = Array(components.indices)
        let shown: [Int?] = indices.count > 5
            ? [indices[0], nil] + indices.suffix(3).map { Optional($0) }
            : indices.map { Optional($0) }
        HStack(spacing: 2) {
            ForEach(Array(shown.enumerated()), id: \.offset) { position, index in
                if position > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.rxInkTertiary)
                }
                if let index {
                    let isLast = index == components.count - 1
                    Button {
                        navigate(path(upTo: index))
                    } label: {
                        Text(components[index])
                            .font(.system(size: 13, weight: isLast ? .semibold : .regular))
                            .foregroundStyle(isLast ? Color.rxInk : Color.rxInkSecondary)
                            .lineLimit(1)
                            .padding(.horizontal, 4)
                            .frame(height: Self.segmentHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isLast)
                } else {
                    Text("…").foregroundStyle(.rxInkSecondary)
                }
            }
        }
        .layoutPriority(1)
    }

    #if os(macOS)
        private static let segmentHeight: CGFloat = 24
    #else
        private static let segmentHeight: CGFloat = 28
    #endif

    func path(upTo index: Int) -> String {
        let components = url.pathComponents.prefix(index + 1)
        guard components.count > 1 else { return "/" }
        return "/" + components.dropFirst().joined(separator: "/")
    }
}
