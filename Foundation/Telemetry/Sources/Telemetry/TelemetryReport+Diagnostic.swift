//
//  TelemetryReport+Diagnostic.swift
//  Telemetry
//
//  Level 1: a crash or hang as MetricKit reported it, with every string
//  gone. What is left is numbers, enums and the call stacks as binary UUID
//  plus offset, which are symbolicated offline against the archived dSYMs.
//

import Foundation

public extension TelemetryReport {
    struct Diagnostic: Codable, Equatable, Sendable {
        public var kind: Kind
        public var appVersion: Version?
        public var osVersion: Version?
        public var exceptionType: Int?
        public var exceptionCode: Int?
        public var signal: Int?
        public var terminationReason: TerminationReason?
        public var objcExceptionName: ObjCExceptionName?
        public var objcExceptionClass: ObjCExceptionClass?
        public var hangDuration: HangDuration?
        public var callStacks: [CallStack]

        public enum Kind: String, Codable, CaseIterable, Sendable {
            case crash, hang, cpuException, diskWriteException
        }

        /// The namespace of MetricKit's termination reason; its free text is dropped.
        public enum TerminationReason: String, Codable, CaseIterable, Sendable {
            case signal, codeSigning, watchdog, jetsam, runningBoard, frontBoard, dyld, libsystem, objc, other
        }

        /// System exception names only; anything else is left out.
        public enum ObjCExceptionName: String, Codable, CaseIterable, Sendable {
            case NSGenericException, NSRangeException, NSInvalidArgumentException
            case NSInternalInconsistencyException, NSMallocException, NSObjectInaccessibleException
            case NSObjectNotAvailableException, NSDestinationInvalidException, NSPortTimeoutException
            case NSInvalidSendPortException, NSInvalidReceivePortException, NSPortSendException
            case NSPortReceiveException, NSCharacterConversionException, NSFileHandleOperationException
            case NSInvalidArchiveOperationException, NSInvalidUnarchiveOperationException
            case NSUndefinedKeyException, NSInconsistentArchiveException, NSParseErrorException
            case NSImageCacheException, NSInternalScriptError
            case NSAccessibilityException, NSWindowServerCommunicationException
            case NSInvalidUbiquitousKeyValueStoreException
            case CALayerInvalidGeometry, CALayerInvalid
        }

        public enum ObjCExceptionClass: String, Codable, CaseIterable, Sendable {
            case NSException
        }

        public enum HangDuration: String, Codable, CaseIterable, Sendable {
            case under1s, under3s, under10s, under30s, over30s

            init(seconds: Double) {
                self = switch seconds {
                case ..<1: .under1s
                case ..<3: .under3s
                case ..<10: .under10s
                case ..<30: .under30s
                default: .over30s
                }
            }
        }
    }

    struct CallStack: Codable, Equatable, Sendable {
        public var threadAttributed: Bool
        public var frames: [Frame]
    }

    /// One frame of MetricKit's call-stack tree. A frame of a binary that is
    /// neither the app nor the system keeps its place in the tree but loses
    /// its UUID and offset.
    struct Frame: Codable, Equatable, Sendable {
        public var origin: Origin
        public var binaryUUID: UUID?
        public var offset: Int?
        public var sampleCount: Int
        public var subFrames: [Frame]

        public enum Origin: String, Codable, CaseIterable, Sendable {
            case app, system, other
        }
    }
}
