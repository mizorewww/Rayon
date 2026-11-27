//
//  PageScaffold+macOS.swift
//  Rayon
//

#if os(macOS)
    import RayonDesign
    import RayonModule
    import SwiftUI

    struct PageScaffold<Leading: View, Trailing: View, Header: View, Content: View>: View {
        let scrolls: Bool
        let search: Binding<String>?
        let searchPrompt: LocalizedStringResource
        let primary: ToolbarAction?
        let trailingMetrics: ToolbarCapsuleMetrics
        let leading: Leading
        let trailing: Trailing
        let header: Header
        let content: Content

        init(
            scrolls: Bool = true,
            search: Binding<String>? = nil,
            searchPrompt: LocalizedStringResource = "Search",
            primary: ToolbarAction? = nil,
            trailingMetrics: ToolbarCapsuleMetrics = .group,
            @ViewBuilder leading: () -> Leading,
            @ViewBuilder trailing: () -> Trailing,
            @ViewBuilder header: () -> Header,
            @ViewBuilder content: () -> Content
        ) {
            self.scrolls = scrolls
            self.search = search
            self.searchPrompt = searchPrompt
            self.primary = primary
            self.trailingMetrics = trailingMetrics
            self.leading = leading()
            self.trailing = trailing()
            self.header = header()
            self.content = content()
        }

        var body: some View {
            Group {
                if scrolls {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            header
                            content
                                .padding(.top, RX.Space.s6)
                        }
                        .padding(.horizontal, RX.Space.s6)
                        .padding(.top, RX.Space.s3)
                        .padding(.bottom, RX.Space.s6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        content
                            .padding(.top, RX.Space.s6)
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .padding(.horizontal, RX.Space.s6)
                    .padding(.top, RX.Space.s3)
                    .padding(.bottom, RX.Space.s6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .pageChrome()
            .pageToolbar(primary: primary, trailingMetrics: trailingMetrics) { leading } trailing: { trailing }
            .modifier(OptionalSearch(text: search, prompt: searchPrompt))
        }
    }

    extension PageScaffold where Header == EmptyView {
        init(
            scrolls: Bool = true,
            search: Binding<String>? = nil,
            searchPrompt: LocalizedStringResource = "Search",
            primary: ToolbarAction? = nil,
            trailingMetrics: ToolbarCapsuleMetrics = .group,
            @ViewBuilder leading: () -> Leading,
            @ViewBuilder trailing: () -> Trailing,
            @ViewBuilder content: () -> Content
        ) {
            self.init(scrolls: scrolls, search: search, searchPrompt: searchPrompt, primary: primary, trailingMetrics: trailingMetrics, leading: leading, trailing: trailing, header: { EmptyView() }, content: content)
        }
    }

    extension View {
        func pageChrome() -> some View {
            rxClearToolbar()
        }
    }

    extension View {
        func pageToolbar<Leading: View, Trailing: View>(
            primary: ToolbarAction? = nil,
            trailingMetrics: ToolbarCapsuleMetrics = .group,
            @ViewBuilder leading: () -> Leading,
            @ViewBuilder trailing: () -> Trailing
        ) -> some View {
            modifier(PageToolbar(leading: leading(), trailing: trailing(), primary: primary, trailingMetrics: trailingMetrics))
        }
    }

    private struct PageToolbar<Leading: View, Trailing: View>: ViewModifier {
        let leading: Leading
        let trailing: Trailing
        let primary: ToolbarAction?
        let trailingMetrics: ToolbarCapsuleMetrics
        @Environment(\.serverToolSwitch) private var toolSwitch

        private var hasTrailing: Bool { Trailing.self != EmptyView.self }

        func body(content: Content) -> some View {
            if #available(macOS 26.0, *) {
                content.toolbar {
                    ToolbarItemGroup(placement: .navigation) { leading }
                    if let toolSwitch {
                        ToolbarItem(placement: .principal) {
                            ServerToolSwitcher(machine: toolSwitch.machine, current: toolSwitch.current)
                        }
                    } else {
                        ToolbarSpacer(.flexible)
                    }
                    if hasTrailing {
                        ToolbarItemGroup(placement: .automatic) {
                            trailing
                        }
                    }
                    if hasTrailing, primary != nil {
                        ToolbarSpacer(.fixed)
                    }
                    if let primary {
                        ToolbarItem(placement: .primaryAction) {
                            primary
                        }
                    }
                }
            } else {
                content.toolbar {
                    ToolbarItemGroup(placement: .navigation) { leading }
                    if let toolSwitch {
                        ToolbarItem(placement: .principal) {
                            ServerToolSwitcher(machine: toolSwitch.machine, current: toolSwitch.current)
                        }
                    } else {
                        ToolbarItem(placement: .principal) {
                            Spacer()
                        }
                    }
                    ToolbarItemGroup(placement: .automatic) {
                        trailing
                    }
                    if let primary {
                        ToolbarItem(placement: .primaryAction) {
                            primary
                        }
                    }
                }
            }
        }
    }

    struct ToolbarCapsuleMetrics {
        var spacing: CGFloat = 0
        var minSlot: CGFloat = 35
        var inset: CGFloat = 4

        static let group = ToolbarCapsuleMetrics()
        static let single = ToolbarCapsuleMetrics(minSlot: 0)
        static let controlGroup = ToolbarCapsuleMetrics(spacing: 9, minSlot: 34.5, inset: 0)
    }

    private struct OptionalSearch: ViewModifier {
        let text: Binding<String>?
        let prompt: LocalizedStringResource

        func body(content: Content) -> some View {
            if let text {
                content.searchable(text: text, placement: .toolbar, prompt: Text(prompt))
            } else {
                content
            }
        }
    }

    struct ToolbarAction: View {
        let title: LocalizedStringResource
        let systemImage: String
        var primary = false
        var isEnabled = true
        let action: () -> Void

        init(_ title: LocalizedStringResource, systemImage: String, primary: Bool = false, isEnabled: Bool = true, action: @escaping () -> Void) {
            self.title = title
            self.systemImage = systemImage
            self.primary = primary
            self.isEnabled = isEnabled
            self.action = action
        }

        var body: some View {
            if primary {
                Button(action: action) {
                    Label(title, systemImage: systemImage)
                }
                .rxPrimaryAction()
                .disabled(!isEnabled)
                .help(title)
            } else {
                Button(action: action) {
                    Label(title, systemImage: systemImage)
                }
                .disabled(!isEnabled)
                .help(title)
            }
        }
    }

#endif
