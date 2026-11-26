//
//  RemoteShellCommand.swift
//  RayonModule
//

import Foundation

public enum RemoteShellCommand {
    /// Hands `script` to `/bin/sh` whatever the login shell is. An exec
    /// channel runs its command through the user's login shell, so POSIX
    /// syntax sent bare fails under fish or csh; wrapped like this every
    /// shell only sees a command name and one single-quoted word. Single
    /// quotes inside the script are closed, escaped and reopened. csh
    /// rejects a newline inside quotes, so the script must be one line.
    /// Mirror of MachineStatus's `ServerStatus.posixShellCommand`;
    /// MachineStatus does not depend on RayonModule, and the two only
    /// share NSRemoteShell, which is Objective-C. User snippets are never
    /// wrapped: they are written for the server's own shell.
    public static func posix(_ script: String) -> String {
        assert(!script.contains("\n"), "csh cannot take a newline inside quotes")
        return "/bin/sh -c '" + script.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
