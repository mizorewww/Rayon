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
        let leading: Leading
        let trailing: Trailing
        let header: Header
        let content: Content

        init(
            scrolls: Bool = true,
            search: Binding<String>? = nil,
            searchPrompt: LocalizedStringResource = "Search",
            primary: ToolbarAction? = nil,
            @ViewBuilder leading: () -> Leading,
            @ViewBuilder trailing: () -> Trailing,
            @ViewBuilder header: () -> Header,
            @ViewBuilder content: () -> Content
        ) {
            self.scrolls = scrolls
            self.search = search
            self.searchPrompt = searchPrompt
            self.primary = primary
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
            .pageToolbar(primary: primary) { leading } trailing: { trailing }
            .modifier(OptionalSearch(text: search, prompt: searchPrompt))
        }
    }

    extension PageScaffold where Header == EmptyView {
        init(
            scrolls: Bool = true,
            search: Binding<String>? = nil,
            searchPrompt: LocalizedStringResource = "Search",
            primary: ToolbarAction? = nil,
            @ViewBuilder leading: () -> Leading,
            @ViewBuilder trailing: () -> Trailing,
            @ViewBuilder content: () -> Content
        ) {
            self.init(scrolls: scrolls, search: search, searchPrompt: searchPrompt, primary: primary, leading: leading, trailing: trailing, header: { EmptyView() }, content: content)
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
            @ViewBuilder leading: () -> Leading,
            @ViewBuilder trailing: () -> Trailing
        ) -> some View {
            modifier(PageToolbar(leading: leading(), trailing: trailing(), primary: primary))
        }
    }

    private struct PageToolbar<Leading: View, Trailing: View>: ViewModifier {
        let leading: Leading
        let trailing: Trailing
        let primary: ToolbarAction?
        @Environment(\.serverToolSwitch) private var toolSwitch

        @Environment(\.hoistsPageToolbar) private var hoisted

        private var hasTrailing: Bool { Trailing.self != EmptyView.self }

        func body(content: Content) -> some View {
            if hoisted {
                content.preference(key: PageToolbarKey.self, value: PageToolbarContent(
                    leading: Leading.self == EmptyView.self ? nil : AnyView(leading),
                    trailing: hasTrailing ? AnyView(trailing) : nil,
                    primary: primary,
                    toolSwitch: toolSwitch
                ))
            } else if #available(macOS 26.0, *) {
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

    /// What the page in front puts in the main window's toolbar. The window
    /// owns one fixed set of toolbar items and swaps their content as pages
    /// change: with the items declared on each page, every switch had AppKit
    /// remove all of them and add new ones, and lay the toolbar out again.
    struct PageToolbarContent: Equatable {
        let leading: AnyView?
        let trailing: AnyView?
        let primary: ToolbarAction?
        let toolSwitch: ServerToolSwitch?

        // Views have no equality; each update of the page hands new ones.
        static func == (_: Self, _: Self) -> Bool { false }
    }

    struct PageToolbarKey: PreferenceKey {
        static var defaultValue: PageToolbarContent? { nil }

        static func reduce(value: inout PageToolbarContent?, nextValue: () -> PageToolbarContent?) {
            value = nextValue() ?? value
        }
    }

    extension EnvironmentValues {
        /// Set by the main window, which shows the page's items in its own
        /// toolbar (`PageToolbarItems`); elsewhere a page declares them itself.
        @Entry var hoistsPageToolbar = false
    }

    /// The main window's toolbar: the same items whatever the page, hidden
    /// where the page in front has nothing for them.
    @available(macOS 26.0, *)
    struct PageToolbarItems: ToolbarContent {
        let content: PageToolbarContent?

        var body: some ToolbarContent {
            ToolbarItem(placement: .navigation) {
                HStack { content?.leading }
                    // Each control keeps its own label; as one element the
                    // stack would take the item's, the first control's.
                    .accessibilityElement(children: .contain)
            }
            .hidden(content?.leading == nil)
            ToolbarItem(placement: .principal) {
                if let toolSwitch = content?.toolSwitch {
                    ServerToolSwitcher(machine: toolSwitch.machine, current: toolSwitch.current)
                }
            }
            .hidden(content?.toolSwitch == nil)
            ToolbarSpacer(.flexible)
                .hidden(content?.toolSwitch != nil)
            ToolbarItem(placement: .automatic) {
                HStack { content?.trailing }
                    // Each control keeps its own label; as one element the
                    // stack would take the item's, the first control's.
                    .accessibilityElement(children: .contain)
            }
            .hidden(content?.trailing == nil)
            ToolbarSpacer(.fixed)
                .hidden(content?.trailing == nil || content?.primary == nil)
            ToolbarItem(placement: .primaryAction) {
                content?.primary
            }
            .hidden(content?.primary == nil)
        }
    }

    extension View {
        /// Shows the toolbar items of the page in front in this view's toolbar.
        @ViewBuilder
        func pageToolbarItems(_ content: Binding<PageToolbarContent?>) -> some View {
            if #available(macOS 26.0, *) {
                environment(\.hoistsPageToolbar, true)
                    .onPreferenceChange(PageToolbarKey.self) { content.wrappedValue = $0 }
                    .toolbar { PageToolbarItems(content: content.wrappedValue) }
            } else {
                self
            }
        }
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
