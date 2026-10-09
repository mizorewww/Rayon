//
//  PageScaffold.swift
//  Rayon (macOS)
//
//  The content column over the translucent window: the page title, then the page body.
//  Page controls live in the native window toolbar, which carries Liquid Glass on
//  macOS 26: navigation on the left, actions on the right with the primary one last,
//  and search as a toolbar search field.
//

import AppKit
import RayonModule
import SwiftUI

struct PageScaffold<Leading: View, Trailing: View, Header: View, Content: View>: View {
    let scrolls: Bool
    let search: Binding<String>?
    let searchPrompt: String
    let leading: Leading
    let trailing: Trailing
    let header: Header
    let content: Content

    init(
        scrolls: Bool = true,
        search: Binding<String>? = nil,
        searchPrompt: String = "Search",
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.scrolls = scrolls
        self.search = search
        self.searchPrompt = searchPrompt
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
        .pageToolbar { leading } trailing: { trailing }
        .modifier(OptionalSearch(text: search, prompt: searchPrompt))
    }
}

extension PageScaffold where Header == EmptyView {
    init(
        scrolls: Bool = true,
        search: Binding<String>? = nil,
        searchPrompt: String = "Search",
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) {
        self.init(scrolls: scrolls, search: search, searchPrompt: searchPrompt, leading: leading, trailing: trailing, header: { EmptyView() }, content: content)
    }
}

extension View {
    /// Lets the toolbar float over the window material. The material itself is
    /// drawn once, behind every page, by MainView: a page that drew its own would
    /// fade with the page during a transition and flash the plain window colour.
    func pageChrome() -> some View {
        toolbarBackground(.hidden, for: .windowToolbar)
    }
}

extension View {
    /// Navigation controls at the leading edge, actions at the trailing edge.
    func pageToolbar<Leading: View, Trailing: View>(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        modifier(PageToolbar(leading: leading(), trailing: trailing()))
    }
}

private struct PageToolbar<Leading: View, Trailing: View>: ViewModifier {
    let leading: Leading
    let trailing: Trailing

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.toolbar {
                ToolbarItemGroup(placement: .navigation) { leading }
                ToolbarSpacer(.flexible)
                ToolbarItemGroup(placement: .automatic) { trailing }
            }
        } else {
            content.toolbar {
                ToolbarItemGroup(placement: .navigation) { leading }
                ToolbarItemGroup(placement: .automatic) { trailing }
            }
        }
    }
}

private struct OptionalSearch: ViewModifier {
    let text: Binding<String>?
    let prompt: String

    func body(content: Content) -> some View {
        if let text {
            content.searchable(text: text, placement: .toolbar, prompt: prompt)
        } else {
            content
        }
    }
}

/// The back button at the left of a sub-page toolbar ("Servers").
struct BackButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "chevron.left")
        }
        .help("Back to \(title)")
    }
}

/// A toolbar action drawn by the system (Liquid Glass on macOS 26): a symbol,
/// with its title as the tooltip and accessibility label (HIG: prefer simple,
/// recognizable symbols in toolbars). The primary action is tinted, not worded.
struct ToolbarAction: View {
    let title: String
    let systemImage: String
    var primary = false
    let action: () -> Void

    init(_ title: String, systemImage: String, primary: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.primary = primary
        self.action = action
    }

    var body: some View {
        if primary {
            Button(action: action) {
                Label(title, systemImage: systemImage)
            }
            .rxPrimaryAction()
            .help(title)
        } else {
            Button(action: action) {
                Label(title, systemImage: systemImage)
            }
            .help(title)
        }
    }
}
