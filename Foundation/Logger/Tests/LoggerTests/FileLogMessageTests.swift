import Foundation
@testable import Logger
import Testing

/// The file log is shareable: a server's name, host or path, or an error
/// description that holds one, must reach only the private unified log.
struct FileLogMessageTests {
    enum FakeSSHError: Error {
        case connectionFailed(String)
        case noExitStatus
    }

    @Test
    func `a fake host reaches only the detail`() {
        let host = "secret-host.example.com:2222"
        let id = UUID()
        let error = FakeSSHError.connectionFailed("Timed out signing in to \(host).")
        let message: FileLogMessage = "server \(id) \(private: host) failed: \(error)"

        #expect(!message.file.contains("secret-host"))
        #expect(message.file == "server \(id.uuidString) <private> failed: FakeSSHError.connectionFailed")
        #expect(message.detail.contains(host))
    }

    @Test
    func `errors are named by their case or code`() {
        #expect(FileLogMessage.Interpolation.caseName(FakeSSHError.noExitStatus) == "FakeSSHError.noExitStatus")
        let cocoa = CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "/Users/someone/secret"])
        let name = FileLogMessage.Interpolation.caseName(cocoa)
        #expect(!name.contains("someone"))
        #expect(name.contains("\(CocoaError.fileNoSuchFile.rawValue)"))
    }
}
