//
//  Form.swift
//  RayonDesign
//
//  Grouped settings forms: caps group label above a `surface` card whose rows are
//  separated by `hairline` dividers.
//

import SwiftUI

/// Stacks its children with a divider between each pair.
public struct RXDividedStack<Content: View>: View {
    let inset: CGFloat
    let content: Content

    public init(inset: CGFloat = 0, @ViewBuilder content: () -> Content) {
        self.inset = inset
        self.content = content()
    }

    public var body: some View {
        if #available(macOS 15.0, iOS 18.0, *) {
            VStack(spacing: 0) {
                Group(subviews: content) { children in
                    ForEach(children) { child in
                        child
                        if child.id != children.last?.id {
                            Hairline().padding(.leading, inset)
                        }
                    }
                }
            }
        } else {
            // The apps need macOS 15 and iOS 18; older systems get no dividers.
            VStack(spacing: 0) { content }
        }
    }
}

/// A settings row: title and one-sentence description, control right-aligned.
public struct RXFormRow<Control: View>: View {
    let title: LocalizedStringResource
    let description: LocalizedStringResource?
    let alignTop: Bool
    let control: Control

    public init(_ title: LocalizedStringResource, description: LocalizedStringResource? = nil, alignTop: Bool = false, @ViewBuilder control: () -> Control) {
        self.title = title
        self.description = description
        self.alignTop = alignTop
        self.control = control()
    }

    public var body: some View {
        HStack(alignment: alignTop ? .top : .center, spacing: RX.Space.s6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.rxBody)
                    .foregroundStyle(.rxInk)
                if let description {
                    HelpText(description)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
        .padding(.vertical, 10)
        .frame(minHeight: RX.formRowMinHeight)
    }
}

/// A boolean preference: title, description and a switch on the right.
public struct SwitchRow: View {
    let title: LocalizedStringResource
    let description: LocalizedStringResource?
    @Binding var isOn: Bool

    public init(_ title: LocalizedStringResource, description: LocalizedStringResource? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.description = description
        _isOn = isOn
    }

    public var body: some View {
        RXFormRow(title, description: description) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .rxSwitchToggle()
                .tint(.rxAccent)
                #if os(macOS) || targetEnvironment(macCatalyst)
                .controlSize(.small)
                #endif
        }
    }
}

/// Page-level section title with optional count and trailing controls.
public struct SectionTitle<Trailing: View>: View {
    let title: LocalizedStringResource
    let count: Int?
    let trailing: Trailing

    public init(_ title: LocalizedStringResource, count: Int? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.count = count
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: RX.Space.s2) {
            Text(title)
                .font(.rxSectionTitle)
                .foregroundStyle(.rxInk)
            if let count {
                CapsLabel(verbatim: count.formatted())
            }
            Spacer(minLength: 0)
            trailing
        }
        .frame(height: RX.controlHeight)
    }
}

public extension SectionTitle where Trailing == EmptyView {
    init(_ title: LocalizedStringResource, count: Int? = nil) {
        self.init(title, count: count) { EmptyView() }
    }
}
