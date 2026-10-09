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
        _VariadicView.Tree(DividedLayout(inset: inset)) {
            content
        }
    }

    private struct DividedLayout: _VariadicView_MultiViewRoot {
        let inset: CGFloat

        @ViewBuilder
        func body(children: _VariadicView.Children) -> some View {
            let last = children.last?.id
            VStack(spacing: 0) {
                ForEach(children) { child in
                    child
                    if child.id != last {
                        Hairline().padding(.leading, inset)
                    }
                }
            }
        }
    }
}

/// A titled group of settings rows on one card.
public struct RXFormSection<Content: View>: View {
    let title: String?
    let footer: String?
    let content: Content

    public init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: RX.Space.s2) {
            if let title, !title.isEmpty {
                CapsLabel(title)
                    .padding(.leading, RX.Space.s4)
            }
            RXDividedStack {
                content
            }
            .padding(.horizontal, RX.Space.s4)
            .background(RXCardBackground())
            if let footer, !footer.isEmpty {
                HelpText(footer)
                    .padding(.horizontal, RX.Space.s4)
            }
        }
    }
}

/// A settings row: title and one-sentence description, control right-aligned.
public struct RXFormRow<Control: View>: View {
    let title: String
    let description: String?
    let alignTop: Bool
    let control: Control

    public init(_ title: String, description: String? = nil, alignTop: Bool = false, @ViewBuilder control: () -> Control) {
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
                if let description, !description.isEmpty {
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
    let title: String
    let description: String?
    @Binding var isOn: Bool

    public init(_ title: String, description: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.description = description
        _isOn = isOn
    }

    public var body: some View {
        RXFormRow(title, description: description) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.rxAccent)
                #if os(macOS)
                .controlSize(.small)
                #endif
        }
    }
}

/// A bounded number: a 200pt continuous slider plus the value in a fixed 52pt column
/// so values line up. The value snaps to `step` but the track draws no tick marks,
/// and the binding is written once, when the drag ends, so a drag does not flood
/// observers (and undo) with intermediate values.
public struct RXSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String
    @State private var draft: Double?

    public init(value: Binding<Double>, in range: ClosedRange<Double>, step: Double = 1, format: @escaping (Double) -> String) {
        _value = value
        self.range = range
        self.step = step
        self.format = format
    }

    private var current: Double { draft ?? value }

    private func snap(_ raw: Double) -> Double {
        guard step > 0 else { return raw }
        let snapped = ((raw - range.lowerBound) / step).rounded() * step + range.lowerBound
        return min(range.upperBound, max(range.lowerBound, snapped))
    }

    public var body: some View {
        HStack(spacing: RX.Space.s2) {
            Slider(
                value: Binding(get: { current }, set: { draft = snap($0) }),
                in: range
            ) { editing in
                guard !editing, let draft else { return }
                if draft != value { value = draft }
                self.draft = nil
            }
            .labelsHidden()
            .tint(.rxAccent)
            .frame(width: 200)
            #if os(macOS)
            .controlSize(.small)
            #endif
            Text(format(current))
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(.rxInk)
                .frame(width: 52, alignment: .trailing)
                .contentTransition(.numericText())
        }
    }
}

/// A settings row with an `RXSlider`.
public struct SliderRow: View {
    let title: String
    let description: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    public init(
        _ title: String,
        description: String? = nil,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double = 1,
        format: @escaping (Double) -> String
    ) {
        self.title = title
        self.description = description
        _value = value
        self.range = range
        self.step = step
        self.format = format
    }

    public var body: some View {
        RXFormRow(title, description: description) {
            RXSlider(value: $value, in: range, step: step, format: format)
        }
    }
}

/// A right-aligned number field with an optional unit.
public struct NumberFieldRow: View {
    let title: String
    let description: String?
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String?

    public init(_ title: String, description: String? = nil, value: Binding<Int>, in range: ClosedRange<Int>, unit: String? = nil) {
        self.title = title
        self.description = description
        _value = value
        self.range = range
        self.unit = unit
    }

    public var body: some View {
        RXFormRow(title, description: description) {
            HStack(spacing: RX.Space.s2) {
                TextField(title, value: Binding(get: { value }, set: { value = min(range.upperBound, max(range.lowerBound, $0)) }), format: .number)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.rx)
                    .frame(width: 72)
                Stepper(title, value: $value, in: range)
                    .labelsHidden()
                if let unit {
                    Text(unit)
                        .font(.rxBody)
                        .foregroundStyle(.rxInkSecondary)
                }
            }
        }
    }
}

/// Page-level section title with optional count and trailing controls.
public struct SectionTitle<Trailing: View>: View {
    let title: String
    let count: Int?
    let trailing: Trailing

    public init(_ title: String, count: Int? = nil, @ViewBuilder trailing: () -> Trailing) {
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
                CapsLabel("\(count)")
            }
            Spacer(minLength: 0)
            trailing
        }
        .frame(height: RX.controlHeight)
    }
}

public extension SectionTitle where Trailing == EmptyView {
    init(_ title: String, count: Int? = nil) {
        self.init(title, count: count) { EmptyView() }
    }
}
