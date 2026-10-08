//
//  PickMachineView.swift
//  mRayon
//
//  Created by Lakr Aream on 2022/3/4.
//

import RayonModule
import SwiftUI

struct PickMachineView: View {
    @StateObject var store = RayonStore.shared

    let canSelectMany: Bool

    @Binding var selection: [RDMachine.ID]
    @State var rawSelection: [RDMachine.ID] = []

    init(selection: Binding<[RDMachine.ID]>, canSelectMany: Bool = true) {
        _selection = selection
        self.canSelectMany = canSelectMany
    }

    private var completion: (([RDMachine.ID]) -> Void)?

    /// MAKE SURE THIS VIEW IS NOT DISMISSABLE BY DRAG
    /// - Parameter completion: only called when touch checkmark button
    init(completion: @escaping (([RDMachine.ID]) -> Void), canSelectMany: Bool = true) {
        self.completion = completion
        self.canSelectMany = canSelectMany
        _selection = Binding<[RDMachine.ID]> { [] } set: { _ in }
    }

    @Environment(\.dismiss) private var dismiss

    var selectionFooter: String {
        rawSelection
            .map { store.machineGroup[$0].name }
            .joined(separator: " ")
    }

    var body: some View {
        List {
            Section {
                if rawSelection.isEmpty {
                    Label("Not Selected", systemImage: "questionmark.square.dashed")
                } else {
                    Label("\(rawSelection.count) Selected", systemImage: "server.rack")
                }
            } header: {
                RXSectionHeader("Selected")
            } footer: {
                if !selectionFooter.isEmpty {
                    Text(selectionFooter)
                } else {
                    Text("<Not Available>")
                }
            }

            Section {
                if store.machineGroup.machines.isEmpty {
                    Label("No servers yet", systemImage: "questionmark.square.dashed")
                } else {
                    ForEach(store.machineGroup.machines) { machine in
                        Button {
                            toggleSelection(for: machine.id)
                        } label: {
                            Label(machine.shortDescription(), systemImage: sysImage(for: machine))

//                            HStack(spacing: 5) {
//                                Image(systemName: sysImage(for: machine))
//                                    .frame(width: 20)
//                                Text(machine.shortDescription())
//                            }
                        }
//                        .disabled(machine.associatedIdentity == nil)
                    }
                }
            } header: {
                RXSectionHeader("Servers")
            }

            Section {
                Button {
                    rawSelection = []
                } label: {
                    Label("Clear Selection", systemImage: "xmark")
                }
                .disabled(rawSelection.isEmpty)
            }
        }
        .rxGroupedList()
        .navigationTitle("Choose Servers")
        .toolbar {
            ToolbarItem {
                Button {
                    dismiss()
                    completion?(rawSelection)
                } label: {
                    Text("Save").bold()
                }
            }
        }
        .onChange(of: rawSelection) { newValue in
            selection = newValue
        }
    }

    func sysImage(for machine: RDMachine) -> String {
//        if machine.associatedIdentity == nil {
//            return "person.fill.questionmark"
//        }
        if rawSelection.contains(machine.id) {
            return "circle.fill"
        }
        return "circle.dashed"
    }

    func toggleSelection(for mid: RDMachine.ID) {
        if canSelectMany {
            if let index = rawSelection.firstIndex(of: mid) {
                rawSelection.remove(at: index)
            } else {
                rawSelection.append(mid)
            }
        } else {
            rawSelection = [mid]
        }
    }
}

struct PickMachineView_Previews: PreviewProvider {
    static var previews: some View {
        createPreview { AnyView(
            PickMachineView { result in
                debugPrint(result)
            }
        ) }
    }
}
