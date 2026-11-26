import Network
import NIOCore
import NIOPosix
@testable import RayonSSH
import XCTest

/// Connection errors read as sentences, whichever layer raised them.
final class SSHErrorWordingTests: XCTestCase {
    func testNetworkAndSocketErrorsReadTheSame() {
        let refused = "connection refused; nothing is listening on that port"
        XCTAssertEqual(SSHTransport.describe(NWError.posix(.ECONNREFUSED)), refused)
        XCTAssertEqual(SSHTransport.describe(IOError(errnoCode: ECONNREFUSED, reason: "connect")), refused)
        XCTAssertEqual(SSHTransport.describe(POSIXError(.ECONNREFUSED)), refused)
        XCTAssertFalse(SSHTransport.describe(NWError.posix(.EPROTO)).contains("POSIXErrorCode"))
    }

    func testChannelErrorsReadAsSentences() {
        XCTAssertEqual(SSHTransport.describe(ChannelError.connectTimeout(.seconds(5))), "the server did not answer in time")
        XCTAssertEqual(SSHTransport.describe(ChannelError.ioOnClosedChannel), "the connection closed")
    }
}
