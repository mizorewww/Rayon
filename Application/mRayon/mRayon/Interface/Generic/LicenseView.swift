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
                Text(loadLicense())
                    .textSelection(.enabled)
                    .font(.footnote)
                    .foregroundStyle(.rxInkSecondary)
            }
            .padding(.bottom)
            .padding(.horizontal)
        }
        .background(RXBackdrop().ignoresSafeArea())
        .navigationTitle("License")
    }

    func loadLicense() -> String {
        guard let bundle = Bundle.main.url(forResource: "LICENSE", withExtension: nil),
              let str = try? String(contentsOfFile: bundle.path)
        else {
            return "Failed to load license info."
        }
        return str
    }
}

struct LicenseView_Previews: PreviewProvider {
    static var previews: some View {
        LicenseView()
    }
}
