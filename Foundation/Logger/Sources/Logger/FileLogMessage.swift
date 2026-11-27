import Foundation

/// A line for the file log, which the person can share (on iOS it shows in
/// Files). It takes only values that name nothing of theirs: ids, numbers,
/// error cases and text marked `public:`. Server names, hosts, paths and
/// error descriptions go in as `private:`; the file gets "<private>" and
/// only the unified log, itself private, gets the value.
public struct FileLogMessage: ExpressibleByStringInterpolation, Sendable {
    /// What the file log gets.
    public let file: String
    /// What the unified log gets, private values included.
    public let detail: String

    public init(stringLiteral value: String) {
        file = value
        detail = value
    }

    public init(stringInterpolation: Interpolation) {
        file = stringInterpolation.file
        detail = stringInterpolation.detail
    }

    public struct Interpolation: StringInterpolationProtocol, Sendable {
        var file = ""
        var detail = ""

        public init(literalCapacity: Int, interpolationCount _: Int) {
            file.reserveCapacity(literalCapacity)
            detail.reserveCapacity(literalCapacity)
        }

        public mutating func appendLiteral(_ literal: String) {
            append(literal)
        }

        public mutating func appendInterpolation(_ id: UUID) {
            append(id.uuidString)
        }

        public mutating func appendInterpolation(_ id: UUID?) {
            append(id?.uuidString ?? "nil")
        }

        public mutating func appendInterpolation(_ number: some BinaryInteger) {
            append(String(number))
        }

        public mutating func appendInterpolation(_ value: Bool) {
            append(String(value))
        }

        /// The error's type and case; its description only privately.
        public mutating func appendInterpolation(_ error: any Error) {
            file += Self.caseName(error)
            detail += "\(Self.caseName(error)): \(error.localizedDescription)"
        }

        /// An enum's case without its payload: a phase whose reason may
        /// name a host is logged as "failed".
        public mutating func appendInterpolation(case value: some Any) {
            let mirror = Mirror(reflecting: value)
            if mirror.displayStyle == .enum, let label = mirror.children.first?.label {
                append(label)
            } else if mirror.displayStyle == .enum, !(Swift.type(of: value) is any CustomStringConvertible.Type) {
                append("\(value)")
            } else {
                file += "<private>"
                detail += "\(value)"
            }
        }

        /// Text known to name nothing of the person's: a table name, a
        /// version, a state.
        public mutating func appendInterpolation(public value: some CustomStringConvertible) {
            append(value.description)
        }

        public mutating func appendInterpolation(private value: some CustomStringConvertible) {
            file += "<private>"
            detail += value.description
        }

        private mutating func append(_ text: String) {
            file += text
            detail += text
        }

        /// "SSHError.connectionFailed", without the case's payload, which
        /// may hold a host; other errors by their domain and code.
        static func caseName(_ error: any Error) -> String {
            let type = String(describing: Swift.type(of: error))
            let mirror = Mirror(reflecting: error)
            if mirror.displayStyle == .enum {
                if let label = mirror.children.first?.label { return "\(type).\(label)" }
                if !(Swift.type(of: error) is any CustomStringConvertible.Type) { return "\(type).\(error)" }
            }
            let error = error as NSError
            return "\(type) (\(error.domain) \(error.code))"
        }
    }
}
