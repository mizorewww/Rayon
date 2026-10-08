//
//  AgreementView.swift
//  mRayon
//
//  Created by Lakr Aream on 2022/3/4.
//

import RayonModule
import SwiftUI

struct AgreementView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
//        NavigationView {
        contentView
//        }
//        .navigationViewStyle(StackNavigationViewStyle())
    }

    var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                Divider().hidden()
                Text(loadLicense())
                    .textSelection(.enabled)
                    .font(.footnote)
                    .foregroundStyle(.rxInkSecondary)
                Divider().hidden()

                HStack {
                    Spacer()
                    Button {
                        UIBridge.requiresConfirmation(
                            message: "Accept the license?",
                            informative: "You have read and agree to the license agreement.",
                            confirmTitle: "Agree",
                            destructive: false
                        ) { yes in
                            if yes {
                                RayonStore.shared.licenseAgreed = true
                                dismiss()
                            }
                        }
                    } label: {
                        Text("I Agree")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.rxPrimary)
                    Spacer()
                }
            }
            .padding()
        }
        .background(RXBackdrop().ignoresSafeArea())
//        .navigationTitle("Agreement")
        .navigationBarTitleDisplayMode(.inline)
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

struct AgreementView_Previews: PreviewProvider {
    static var previews: some View {
        AgreementView()
    }
}
