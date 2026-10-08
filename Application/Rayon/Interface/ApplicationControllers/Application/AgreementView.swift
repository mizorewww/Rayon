//
//  AgreementView.swift
//  Rayon
//
//  Created by Lakr Aream on 2022/2/13.
//

import RayonModule
import SwiftUI

struct AgreementView: View {
    @Environment(\.dismiss) private var dismiss

    @State var checkBox = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("License Agreement").font(.headline)
            Divider()
            ScrollView {
                Text(loadLicense())
                    .textSelection(.enabled)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
            }
            .frame(width: 600, height: 250)
            Divider()
            HStack {
                Toggle("I fully understand the license agreements and agree with it.", isOn: $checkBox)
                Spacer()
                // HIG: enable the continue action only after required input is provided,
                // instead of presenting an error alert.
                Button {
                    RayonStore.shared.licenseAgreed = true
                    dismiss()
                } label: {
                    Text("Done")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!checkBox)
            }
        }
        .padding()
    }

    func loadLicense() -> String {
        guard let bundle = Bundle.main.url(forResource: "EULA", withExtension: nil),
              let str = try? String(contentsOfFile: bundle.path)
        else {
            return "Failed to load license info."
        }
        return str
    }
}
