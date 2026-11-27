//
//  Controls.swift
//  RayonDesign
//
//  Buttons, segmented controls, text fields and search fields. Every control is 28pt tall.
//

import SwiftUI

// MARK: - Buttons

public struct RXButtonStyle: ButtonStyle {
    public enum Kind {
        /// `surface` fill, 1px `control-border`.
        case bordered
        /// `accent` fill; one per view at most.
        case primary
        /// Destructive confirmation only.
        case danger
        /// Toolbar text actions.
        case plain
    }

    public enum Size {
        case regular
        case small
    }

    let kind: Kind
    let size: Size
    let iconOnly: Bool

    public init(_ kind: Kind = .bordered, size: Size = .regular, iconOnly: Bool = false) {
        self.kind = kind
        self.size = size
        self.iconOnly = iconOnly
    }

    public func makeBody(configuration: Configuration) -> some View {
        RXButtonBody(configuration: configuration, kind: kind, size: size, iconOnly: iconOnly)
    }
}

private struct RXButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: RXButtonStyle.Kind
    let size: RXButtonStyle.Size
    let iconOnly: Bool

    @Environment(\.isEnabled) private var isEnabled

    var height: CGFloat { size == .small ? RX.smallControlHeight : RX.controlHeight }

    @State private var hovered = false

    var body: some View {
        configuration.label
            .font(size == .small ? .system(size: 12, weight: weight) : .system(size: 13, weight: weight))
            .labelStyle(RXButtonLabelStyle(iconOnly: iconOnly))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(foreground)
            .padding(.horizontal, iconOnly ? 0 : (kind == .plain ? 8 : (size == .small ? 10 : 14)))
            .frame(width: iconOnly ? height : nil, height: height)
            .background(background)
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.65)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.rxQuick, value: configuration.isPressed)
            .animation(.rxQuick, value: hovered)
            #if os(macOS)
            .onHover { hovered = $0 }
            #endif
    }

    var weight: Font.Weight {
        kind == .primary || kind == .danger ? .semibold : .medium
    }

    var foreground: Color {
        switch kind {
        case .bordered: return isEnabled ? .rxInk : .rxInkTertiary
        case .primary: return isEnabled ? .white : .rxInkSecondary
        case .danger: return isEnabled ? .white : .rxInkSecondary
        case .plain: return hovered && isEnabled ? .rxInk : .rxInkSecondary
        }
    }

    /// Capsules with fills only: Liquid Glass controls carry no outline.
    @ViewBuilder var background: some View {
        let shape = Capsule()
        switch kind {
        case .bordered:
            shape.fill(Color.primary.opacity(isEnabled ? (configuration.isPressed ? 0.16 : (hovered ? 0.11 : 0.07)) : 0.05))
        case .primary:
            if isEnabled {
                shape.fill(Color.rxAccent.opacity(configuration.isPressed ? 0.85 : 1))
                    .shadow(color: Color.rxAccent.opacity(0.25), radius: 6, y: 2)
            } else {
                shape.fill(Color.primary.opacity(0.10))
            }
        case .danger:
            if isEnabled {
                shape.fill(Color.rxDanger.opacity(configuration.isPressed ? 0.85 : 1))
            } else {
                shape.fill(Color.primary.opacity(0.10))
            }
        case .plain:
            shape.fill(Color.primary.opacity(configuration.isPressed ? 0.12 : (hovered && isEnabled ? 0.07 : 0)))
        }
    }
}

private struct RXButtonLabelStyle: LabelStyle {
    let iconOnly: Bool
    func makeBody(configuration: Configuration) -> some View {
        if iconOnly {
            configuration.icon
                .font(.system(size: 14, weight: .regular))
        } else {
            HStack(spacing: 6) {
                configuration.icon
                    .font(.system(size: 13, weight: .regular))
                configuration.title
            }
        }
    }
}

public extension ButtonStyle where Self == RXButtonStyle {
    /// Bordered 28pt button.
    static var rx: RXButtonStyle { RXButtonStyle() }
    /// The one primary action of a view.
    static var rxPrimary: RXButtonStyle { RXButtonStyle(.primary) }
    static var rxDanger: RXButtonStyle { RXButtonStyle(.danger) }
    static var rxPlain: RXButtonStyle { RXButtonStyle(.plain) }

    static func rx(_ kind: RXButtonStyle.Kind = .bordered, size: RXButtonStyle.Size = .regular, iconOnly: Bool = false) -> RXButtonStyle {
        RXButtonStyle(kind, size: size, iconOnly: iconOnly)
    }
}

/// Icon-only 28×28 button with an accessible label and tooltip.
public struct RXIconButton: View {
    let title: String
    let systemImage: String
    let kind: RXButtonStyle.Kind
    let size: RXButtonStyle.Size
    let action: () -> Void

    public init(
        _ title: String,
        systemImage: String,
        kind: RXButtonStyle.Kind = .bordered,
        size: RXButtonStyle.Size = .regular,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.kind = kind
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(RXButtonStyle(kind, size: size, iconOnly: true))
        .help(title)
        .accessibilityLabel(title)
    }
}

// MARK: - Text fields

public extension View {
    /// The field chrome used by text fields, pop-ups and editors.
    func rxFieldBackground() -> some View {
        background(
            RoundedRectangle(cornerRadius: RX.Radius.lg, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: RX.Radius.lg, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        )
    }
}

/// Caption label above a field, optional help or error underneath.
public struct RXField<Content: View>: View {
    let label: String
    let help: String?
    let error: String?
    let content: Content

    public init(_ label: String, help: String? = nil, error: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.help = help
        self.error = error
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CapsLabel(label)
            content
            if let error, !error.isEmpty {
                HelpText(error, isError: true)
            } else if let help, !help.isEmpty {
                HelpText(help)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A read-only value drawn like a field.
public struct RXValueField: View {
    let text: String
    let placeholder: String
    let monospaced: Bool

    public init(_ text: String, placeholder: String = "", monospaced: Bool = false) {
        self.text = text
        self.placeholder = placeholder
        self.monospaced = monospaced
    }

    public var body: some View {
        Text(text.isEmpty ? placeholder : text)
            .font(monospaced ? .rxCode : .rxBody)
            .foregroundStyle(text.isEmpty ? Color.rxInkSecondary : Color.rxInk)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .frame(height: RX.controlHeight)
            .background(
                RoundedRectangle(cornerRadius: RX.Radius.lg, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .textSelection(.enabled)
    }
}

/// A 28pt filter field at the left of a toolbar. Filters the current list live.
public struct RXSearchField: View {
    let prompt: String
    @Binding var text: String
    let width: CGFloat?

    public init(_ prompt: String, text: Binding<String>, width: CGFloat? = 220) {
        self.prompt = prompt
        _text = text
        self.width = width
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.rxInkSecondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.rxBody)
                .disableAutocorrection(true)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.rxInkSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(width: width, height: RX.controlHeight)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}

// MARK: - Liquid Glass actions

public extension View {
    /// The one primary action of a view: Liquid Glass prominent on macOS 26 / iOS 26,
    /// a prominent bordered capsule before that.
    @ViewBuilder
    func rxPrimaryAction() -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            buttonStyle(.glassProminent).tint(.rxAccent)
        } else {
            buttonStyle(.borderedProminent).tint(.rxAccent)
        }
    }

}
