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

    func testCausesComeFromTheErrorTypeNotItsWording() {
        XCTAssertEqual(SSHTransport.cause(of: NWError.posix(.ECONNREFUSED)), .refused)
        XCTAssertEqual(SSHTransport.cause(of: IOError(errnoCode: ECONNREFUSED, reason: "connect")), .refused)
        XCTAssertEqual(SSHTransport.cause(of: POSIXError(.ECONNREFUSED)), .refused)
        XCTAssertEqual(SSHTransport.cause(of: NWError.dns(-65554)), .hostNotFound)
        XCTAssertEqual(SSHTransport.cause(of: ChannelError.connectTimeout(.seconds(5))), .timedOut)
        XCTAssertEqual(SSHTransport.cause(of: NWError.posix(.ETIMEDOUT)), .timedOut)
        XCTAssertEqual(SSHTransport.cause(of: ChannelError.eof), .closed)
        XCTAssertEqual(SSHTransport.cause(of: POSIXError(.ECONNRESET)), .closed)
        XCTAssertEqual(SSHTransport.cause(of: IOError(errnoCode: EPIPE, reason: "write")), .closed)
        XCTAssertEqual(SSHTransport.cause(of: NWError.posix(.EPROTO)), .other)
        XCTAssertEqual(SSHTransport.cause(of: CancellationError()), .other)
    }
}
