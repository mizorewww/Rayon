//
//  FileTable+macOS.swift
//  Rayon
//
//  A folder's files in the system's Table: resizable columns, keyboard
//  navigation, a context menu, and double-click or Return to open.
//

#if os(macOS)
    import RayonModule
    import SwiftUI

    @MainActor private let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    struct FileTable<MenuContent: View>: View {
        typealias File = FileTransferContext.RemoteFile

        let files: [File]
        let folder: String
        let selection: File.ID?
        let select: (File.ID?) -> Void
        let open: (File) -> Void
        @ViewBuilder let menu: (File) -> MenuContent

        var body: some View {
            Table(files, selection: Binding(get: { selection }, set: { select($0) })) {
                TableColumn("Name") { file in
                    Label {
                        Text(file.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } icon: {
                        Image(systemName: file.isFolder ? "folder" : (file.fstat.isLink ? "link" : "doc"))
                            .foregroundStyle(file.isFolder ? Color.rxAccent : Color.rxInkSecondary)
                    }
                }
                .width(min: 140, ideal: 180)
                TableColumn("Size") { file in
                    Text(file.isFolder ? "—" : RXFormat.bytesString(Double(file.fstat.size ?? 0)))
                        .monospacedDigit()
                        .foregroundStyle(file.isFolder ? Color.rxInkSecondary : Color.rxInk)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 50, ideal: 60, max: 120)
                TableColumn("Modified") { file in
                    Text(file.fstat.modificationDate.map { fileDateFormatter.string(from: $0) } ?? "—")
                        .foregroundStyle(.rxInkSecondary)
                }
                .width(min: 90, ideal: 140, max: 220)
                TableColumn("Permissions") { file in
                    Text(file.fstat.permissionDescription)
                        .font(.rxCode)
                        .foregroundStyle(.rxInkSecondary)
                }
                .width(min: 80, ideal: 95, max: 140)
                TableColumn("Owner") { file in
                    Text(file.fstat.ownerUID == 0 ? "root" : String(file.fstat.ownerUID))
                        .monospacedDigit()
                        .foregroundStyle(.rxInkSecondary)
                }
                .width(min: 40, ideal: 50, max: 100)
            }
            .contextMenu(forSelectionType: File.ID.self) { chosen in
                if let file = files.first(where: { chosen.contains($0.id) }) { menu(file) }
            } primaryAction: { chosen in
                if let file = files.first(where: { chosen.contains($0.id) }) { open(file) }
            }
            // Another folder starts at its top.
            .id(folder)
        }
    }

#endif
