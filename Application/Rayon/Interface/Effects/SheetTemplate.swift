//
//  SwiftUIView.swift
//  Rayon (macOS)
//
//  Created by Lakr Aream on 2022/2/9.
//

import RayonModule
import SwiftUI

enum SheetTemplate {
    typealias Confirmed = Bool

    @MainActor static func makeSheet(
        title: String,
        body: AnyView,
        complete: @escaping (Confirmed) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Divider()
            body.expended()
            Divider()
            HStack {
                Button { complete(false) } label: { Text("Cancel") }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                // HIG: the most likely choice should be primary and respond to Return.
                Button { complete(true) } label: { Text("Done") }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }

    static func makeProgress(text: String) -> some View {
        ProgressView(text)
            .frame(width: 400, height: 200)
    }

    static func makeErrorAlert(with error: Error, delay: Double = 0) {
        mainActorUI(delay: delay) {
            let alert = NSAlert()
            // HIG: use caution symbols sparingly; routine errors don't warrant one.
            alert.messageText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            alert.beginSheetModal(for: NSApp.keyWindow ?? NSWindow()) { _ in
            }
        }
    }
}
