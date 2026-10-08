//
//  OnMainThread.swift
//
//
//  Created by Lakr Aream on 2022/3/1.
//

import Foundation

/// Runs `run` on the main thread. Zero-delay calls made from the main thread
/// execute synchronously, preserving the legacy callback ordering; anything
/// else is dispatched to the main queue.
/// - Parameter run: the job to be fired on the main thread
public func onMainThread(delay: Double = 0, run: @escaping () -> Void) {
    // Preserve the legacy model callbacks without claiming the models are Sendable.
    nonisolated(unsafe) let run = run
    guard delay == 0, Thread.isMainThread else {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            run()
        }
        return
    }
    run()
}
