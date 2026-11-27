//
//  AgreementView+iOS.swift
//  Rayon
//
//  Created by Lakr Aream on 2022/3/4.
//

#if os(iOS)
    import RayonModule
    import SwiftUI

    struct AgreementView: View {
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            contentView
        }

        var contentView: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    Divider().hidden()
                    LicenseTextView(resource: "EULA")
                    Divider().hidden()

                    HStack {
                        Spacer()
                        Button {
                            Indicator.confirm(
                                message: "Accept the license?",
                                confirmTitle: "Agree"
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
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    struct AgreementView_Previews: PreviewProvider {
        static var previews: some View {
            AgreementView()
        }
    }

#endif
