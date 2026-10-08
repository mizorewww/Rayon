//
//  MonitorView.swift
//  mRayon
//
//  Created by Lakr Aream on 2022/3/3.
//

import MachineStatus
import MachineStatusView
import RayonModule
import SwiftUI

struct MonitorView: View {
    @StateObject var context: MonitorContext

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if context.closed {
                PlaceholderView("Connection Closed", img: .connectionBroken)
                    .expended()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ServerStatusViews
                            .createBaseStatusView(withContext: context.status)
                    }
                    .padding()
                }
                .toolbar {
                    ToolbarItem {
                        Button {
                            MonitorManager.shared.end(for: context.id)
                            dismiss()
                        } label: {
                            Label("Close Monitor", systemImage: "xmark")
                        }
                    }
                }
            }
        }
        .navigationTitle("Monitor - \(context.machine.name)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
