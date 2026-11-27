//
//  EditorForm.swift
//  Rayon
//
//  What the server, identity and snippet editors share: a labelled field
//  for a Form, and the sheet they are shown in.
//

import RayonDesign
import SwiftUI

/// A text field with its label leading the row and its text left-aligned.
/// LabeledContent around a field whose own label is hidden: a labelled
/// field in a grouped Form right-aligns its text on the Mac whatever its
/// alignment, and shows only the prompt on iPhone and iPad.
struct FormField: View {
    let title: LocalizedStringResource
    @Binding var text: String
    var prompt: Text?
    var secure = false
    /// Commands, addresses and keys: monospaced, never corrected.
    var code = false

    init(_ title: LocalizedStringResource, text: Binding<String>, prompt: Text? = nil, secure: Bool = false, code: Bool = false) {
        self.title = title
        _text = text
        self.prompt = prompt
        self.secure = secure
        self.code = code
    }

    var body: some View {
        LabeledContent {
            field
                .labelsHidden()
                .multilineTextAlignment(.leading)
            #if os(iOS)
                .textInputAutocapitalization(code ? .never : nil)
            #endif
        } label: {
            Text(title)
        }
    }

    @ViewBuilder private var field: some View {
        Group {
            if secure {
                SecureField(text: $text, prompt: prompt) { Text(title) }
            } else {
                TextField(text: $text, prompt: prompt) { Text(title) }
            }
        }
        .font(code ? .rxCode : nil)
        .autocorrectionDisabled(code)
    }
}

extension View {
    /// An editor's title, size and navigation bar. A Mac sheet has no
    /// navigation bar, so its title heads the form; its Cancel and Save,
    /// placed as the toolbar's cancellation and confirmation actions, sit
    /// below it.
    func editorSheet(_ title: LocalizedStringResource) -> some View {
        #if os(macOS)
            VStack(spacing: 0) {
                Text(title)
                    .font(.headline)
                    .padding(.top, RX.Space.s4)
                self
            }
            .frame(width: 540)
            .frame(minHeight: 360, idealHeight: 620)
        #else
            NavigationStack {
                navigationTitle(Text(title))
                    .navigationBarTitleDisplayMode(.inline)
            }
        #endif
    }
}
