//
//  LogRedirect.swift
//  mRayon
//
//  Created by Lakr Aream on 2022/3/14.
//

import SwiftUI

class LogRedirect {
    static let shared = LogRedirect()

    var handler: FileHandle?
    var path: URL?

    private init() {
        if let url = FileManager
            .default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("me.mizorewww.diag.log")
        {
            path = url
            // Keep the last run's log as .prev.log instead of wiping it: the
            // diagnostics of a session that crashed survive the relaunch.
            let prev = url.deletingLastPathComponent()
                .appendingPathComponent("me.mizorewww.diag.prev.log")
            try? FileManager.default.removeItem(at: prev)
            try? FileManager.default.moveItem(at: url, to: prev)
            FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)
            handler = try? FileHandle(forWritingTo: url)
            checkPipe()
        }
    }

    func checkPipe() {
        guard let handler = handler, let path = path?.path else {
            return
        }
        #if DEBUG
            guard UserDefaults.standard.value(forKey: "me.mizorewww.redirect.diag") as? Bool ?? false else {
                return
            }
        #endif
        debugPrint("calling dup2 on stdout and stderr with \(path)")
        dup2(handler.fileDescriptor, STDOUT_FILENO)
        dup2(handler.fileDescriptor, STDERR_FILENO)
    }
}
