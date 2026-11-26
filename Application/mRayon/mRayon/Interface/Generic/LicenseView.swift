//
//  LicenseView.swift
//  mRayon
//
//  Created by Lakr Aream on 2022/3/4.
//

import RayonModule
import SwiftUI

struct LicenseView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Divider().hidden()
                LicenseTextView(resource: "LICENSE")
            }
            .padding(.bottom)
            .padding(.horizontal)
        }
        .background(RXBackdrop().ignoresSafeArea())
        .navigationTitle("License")
    }
}

/// A bundled text (EULA, LICENSE), read off the main thread: the read would
/// otherwise run synchronously inside `body`.
struct LicenseTextView: View {
    let resource: String
    @State private var text = ""

    var body: some View {
        Text(text)
            .textSelection(.enabled)
            .font(.footnote)
            .foregroundStyle(.rxInkSecondary)
            .task {
                guard text.isEmpty else { return }
                text = await Self.load(resource: resource)
            }
    }

    static func load(resource: String) async -> String {
        await Task.detached {
            guard let bundle = Bundle.main.url(forResource: resource, withExtension: nil),
                  let str = try? String(contentsOfFile: bundle.path)
            else {
                return "Failed to load license info."
            }
            return str
        }.value
    }
}

struct LicenseView_Previews: PreviewProvider {
    static var previews: some View {
        LicenseView()
    }
}
