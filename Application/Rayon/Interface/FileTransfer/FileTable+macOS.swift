//
//  FileTable+macOS.swift
//  Rayon
//
//  A folder's files in the system's Table: resizable and sortable columns,
//  keyboard navigation, several files chosen at once, a context menu, and
//  double-click or Return to open.
//

#if os(macOS)
    import RayonModule
    import SwiftUI

    struct FileTable: View {
        typealias File = FileTransferContext.RemoteFile

        @ObservedObject var browser: FileBrowser

        var body: some View {
            Table(browser.files, selection: $browser.selection, sortOrder: $browser.sortOrder) {
                TableColumn("Name", sortUsing: RemoteFileComparator(.name)) { file in
                    Label {
                        Text(file.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } icon: {
                        Image(systemName: file.symbol)
                            .foregroundStyle(file.isFolder ? Color.rxAccent : Color.rxInkSecondary)
                    }
                }
                .width(min: 140, ideal: 180)
                TableColumn("Size", sortUsing: RemoteFileComparator(.size)) { file in
                    Text(file.sizeText)
                        .monospacedDigit()
                        .foregroundStyle(file.isFolder ? Color.rxInkSecondary : Color.rxInk)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 50, ideal: 60, max: 120)
                TableColumn("Modified", sortUsing: RemoteFileComparator(.modified)) { file in
                    Text(file.modifiedText)
                        .foregroundStyle(.rxInkSecondary)
                }
                .width(min: 90, ideal: 140, max: 220)
                TableColumn("Kind", sortUsing: RemoteFileComparator(.kind)) { file in
                    Text(file.kind)
                        .lineLimit(1)
                        .foregroundStyle(.rxInkSecondary)
                }
                .width(min: 60, ideal: 100, max: 180)
                TableColumn("Permissions") { file in
                    Text(file.fstat.permissionDescription)
                        .font(.rxCode)
                        .foregroundStyle(.rxInkSecondary)
                }
                .width(min: 80, ideal: 95, max: 140)
                TableColumn("Owner") { file in
                    Text(file.ownerText)
                        .monospacedDigit()
                        .foregroundStyle(.rxInkSecondary)
                }
                .width(min: 40, ideal: 50, max: 100)
            }
            .contextMenu(forSelectionType: File.ID.self) { chosen in
                let files = browser.files.filter { chosen.contains($0.id) }
                if !files.isEmpty { FileActionsMenu(browser: browser, files: files) }
            } primaryAction: { chosen in
                // Several files open as one would: folders cannot all be shown.
                if chosen.count == 1, let file = browser.files.first(where: { chosen.contains($0.id) }) { browser.open(file) }
            }
            // Another folder starts at its top.
            .id(browser.context.currentDir)
        }
    }

#endif
