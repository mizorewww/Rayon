//
//  TransferCard.swift
//  Rayon
//
//  The transfer in progress: the file, how many of how many, the speed, and
//  Cancel.
//

import RayonModule
import SwiftUI

struct TransferCard: View {
    @ObservedObject var context: FileTransferContext

    var body: some View {
        let total = context.totalProgress
        let current = context.currentProgress
        let fraction: Double? = total.totalUnitCount > 0
            ? total.fractionCompleted
            : (current.totalUnitCount > 0 ? current.fractionCompleted : nil)
        var detail: [String] = []
        if total.totalUnitCount > 1 {
            detail.append(String(localized: "\(total.completedUnitCount) of \(total.totalUnitCount)"))
        }
        if context.currentSpeed > 0 {
            detail.append(RXFormat.rateString(Double(context.currentSpeed)))
        }
        let name = context.currentProcessingFile.isEmpty
            ? (context.currentHint.isEmpty ? String(localized: "Working…") : context.currentHint)
            : URL(fileURLWithPath: context.currentProcessingFile).lastPathComponent
        return VStack(alignment: .leading, spacing: RX.Space.s2) {
            CardHead("Transfer")
            ProgressRowView(
                title: name,
                detail: detail.joined(separator: " · "),
                fraction: fraction,
                cancel: context.currentProgressCancelable && context.continueCurrentProgress
                    ? { context.continueCurrentProgress = false }
                    : nil
            )
        }
        .rxCard()
    }
}
