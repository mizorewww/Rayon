//
//  RemoteFile+Display.swift
//  Rayon
//
//  How a remote file's details read in the file lists.
//

import RayonModule
import SwiftUI

@MainActor private let fileDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    formatter.doesRelativeDateFormatting = true
    return formatter
}()

extension FileTransferContext.RemoteFile {
    var symbol: String {
        if isFolder { return "folder" }
        if fstat.isLink { return "link" }
        return "doc"
    }

    var sizeText: String {
        isFolder ? "—" : RXFormat.bytesString(Double(fstat.size ?? 0))
    }

    @MainActor var modifiedText: String {
        fstat.modificationDate.map { fileDateFormatter.string(from: $0) } ?? "—"
    }

    var ownerText: String {
        fstat.ownerUID == 0 ? "root" : String(fstat.ownerUID)
    }
}

extension RemoteFileComparator.Field {
    var title: LocalizedStringResource {
        switch self {
        case .name: "Name"
        case .size: "Size"
        case .modified: "Modified"
        case .kind: "Kind"
        }
    }
}
