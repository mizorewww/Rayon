//
//  PageScaffold+macOS.swift
//  Rayon
//

#if os(macOS)
    import RayonDesign
    import RayonModule
    import SwiftUI

    struct PageScaffold<Header: View, Content: View>: View {
        let scrolls: Bool
        let search: Binding<String>?
        let searchPrompt: LocalizedStringResource
        let primary: ToolbarAction?
        let leading: [AnyView]
        let trailing: [AnyView]
        let header: Header
        let content: Content

        init(
            scrolls: Bool = true,
            search: Binding<String>? = nil,
            searchPrompt: LocalizedStringResource = "Search",
            primary: ToolbarAction? = nil,
            @ToolbarControls leading: () -> [AnyView],
            @ToolbarControls trailing: () -> [AnyView],
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
            .modifier(PageToolbar(leading: leading, trailing: trailing, primary: primary))
            .modifier(OptionalSearch(text: search, prompt: searchPrompt))
        }
    }

    extension PageScaffold where Header == EmptyView {
        init(
            scrolls: Bool = true,
            search: Binding<String>? = nil,
            searchPrompt: LocalizedStringResource = "Search",
            primary: ToolbarAction? = nil,
            @ToolbarControls leading: () -> [AnyView],
            @ToolbarControls trailing: () -> [AnyView],
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
        func pageToolbar(
            primary: ToolbarAction? = nil,
            @ToolbarControls leading: () -> [AnyView],
            @ToolbarControls trailing: () -> [AnyView]
        ) -> some View {
            modifier(PageToolbar(leading: leading(), trailing: trailing(), primary: primary))
        }
    }

    /// Collects a page's toolbar controls one by one, so each becomes a
    /// toolbar item of its own, with its own label, in VoiceOver and in the
    /// overflow menu of a narrow window.
    @resultBuilder
    enum ToolbarControls {
        static func buildExpression(_ control: some View) -> [AnyView] { [AnyView(control)] }
        static func buildBlock(_ parts: [AnyView]...) -> [AnyView] { parts.flatMap(\.self) }
        static func buildOptional(_ part: [AnyView]?) -> [AnyView] { part ?? [] }
        static func buildEither(first part: [AnyView]) -> [AnyView] { part }
        static func buildEither(second part: [AnyView]) -> [AnyView] { part }
    }

    private struct PageToolbar: ViewModifier {
        let leading: [AnyView]
        let trailing: [AnyView]
        let primary: ToolbarAction?
        @Environment(\.serverToolSwitch) private var toolSwitch

        @Environment(\.hoistsPageToolbar) private var hoisted

        func body(content: Content) -> some View {
            if hoisted {
                let _ = assert(max(leading.count, trailing.count) <= PageToolbarContent.slots, "More toolbar controls than PageToolbarContent.slots")
                content.preference(key: PageToolbarKey.self, value: PageToolbarContent(
                    leading: leading,
                    trailing: trailing,
                    primary: primary,
                    toolSwitch: toolSwitch
                ))
            } else if #available(macOS 26.0, *) {
                content.toolbar {
                    ToolbarItemGroup(placement: .navigation) { controls(leading) }
                    if let toolSwitch {
                        ToolbarItem(placement: .principal) {
                            ServerToolSwitcher(machine: toolSwitch.machine, current: toolSwitch.current)
                        }
                    } else {
                        ToolbarSpacer(.flexible)
                    }
                    if !trailing.isEmpty {
                        ToolbarItemGroup(placement: .automatic) { controls(trailing) }
                    }
                    if !trailing.isEmpty, primary != nil {
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
                    ToolbarItemGroup(placement: .navigation) { controls(leading) }
                    if let toolSwitch {
                        ToolbarItem(placement: .principal) {
                            ServerToolSwitcher(machine: toolSwitch.machine, current: toolSwitch.current)
                        }
                    } else {
                        ToolbarItem(placement: .principal) {
                            Spacer()
                        }
                    }
                    ToolbarItemGroup(placement: .automatic) { controls(trailing) }
                    if let primary {
                        ToolbarItem(placement: .primaryAction) {
                            primary
                        }
                    }
                }
            }
        }

        private func controls(_ views: [AnyView]) -> some View {
            ForEach(views.indices, id: \.self) { views[$0] }
        }
    }

    /// What the page in front puts in the main window's toolbar. The window
    /// owns one fixed set of toolbar items and swaps their content as pages
    /// change: with the items declared on each page, every switch had AppKit
    /// remove all of them and add new ones, and lay the toolbar out again.
    struct PageToolbarContent {
        let leading: [AnyView]
        let trailing: [AnyView]
        let primary: ToolbarAction?
        let toolSwitch: ServerToolSwitch?

        /// The toolbar items on each side: enough for the page with the most
        /// controls on a side (the terminal's leading six). A fixed count
        /// keeps the items in place as pages change.
        static let slots = 6
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
    /// where the page in front has nothing for them. Each control has an
    /// item of its own: one item holding them all would be named after its
    /// first control and be one entry in the overflow menu.
    @available(macOS 26.0, *)
    struct PageToolbarItems: ToolbarContent {
        let content: PageToolbarContent?

        var body: some ToolbarContent {
            PageToolbarSlots(placement: .navigation, controls: content?.leading ?? [])
            ToolbarItem(placement: .principal) {
                if let toolSwitch = content?.toolSwitch {
                    ServerToolSwitcher(machine: toolSwitch.machine, current: toolSwitch.current)
                }
            }
            .hidden(content?.toolSwitch == nil)
            ToolbarSpacer(.flexible)
                .hidden(content?.toolSwitch != nil)
            PageToolbarSlots(placement: .automatic, controls: content?.trailing ?? [])
            ToolbarSpacer(.fixed)
                .hidden(content?.trailing.isEmpty ?? true || content?.primary == nil)
            ToolbarItem(placement: .primaryAction) {
                content?.primary
            }
            .hidden(content?.primary == nil)
        }
    }

    /// `PageToolbarContent.slots` items at one place, each showing one of
    /// `controls` and hidden past their count. Written out rather than made
    /// with ForEach, whose toolbar items the window does not show.
    @available(macOS 26.0, *)
    private struct PageToolbarSlots: ToolbarContent {
        let placement: ToolbarItemPlacement
        let controls: [AnyView]

        var body: some ToolbarContent {
            slot(0)
            slot(1)
            slot(2)
            slot(3)
            slot(4)
            slot(5)
        }

        private func slot(_ index: Int) -> some ToolbarContent {
            ToolbarItem(placement: placement) {
                if index < controls.count { controls[index] }
            }
            .hidden(index >= controls.count)
        }
    }

    extension View {
        /// Shows the toolbar items of the page in front in this view's toolbar.
        /// They are read where they are drawn, in the same update as the
        /// page: views have no equality, so held in state each of the page's
        /// updates would also update the window's whole view, and could do
        /// so more than once a frame.
        @ViewBuilder
        func pageToolbarItems() -> some View {
            if #available(macOS 26.0, *) {
                environment(\.hoistsPageToolbar, true)
                    .backgroundPreferenceValue(PageToolbarKey.self) { content in
                        Color.clear.toolbar { PageToolbarItems(content: content) }
                    }
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
