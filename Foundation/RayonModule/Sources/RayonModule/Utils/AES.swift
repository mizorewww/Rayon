//
//  AES.swift
//  PTFoundation
//
//  Created by Lakr Aream on 12/15/20.
//

import CommonCrypto
import Foundation
import Keychain

public struct AES: Sendable {
    private let key: Data
    private let iv: Data

    public static let shared: AES = {
        #if DEBUG
            var keyBuilder = "fdaisohfiuhfq34hifgraskhfiarhfgui34hibrfiuef"
            #if os(macOS)
                let platformExpert = IOServiceGetMatchingService(
                    kIOMasterPortDefault,
                    IOServiceMatching("IOPlatformExpertDevice")
                )
                if platformExpert > 0,
                   let serialNumber = (
                       IORegistryEntryCreateCFProperty(
                           platformExpert,
                           kIOPlatformSerialNumberKey as CFString,
                           kCFAllocatorDefault,
                           0
                       )
                       .takeUnretainedValue() as? String
                   )
                {
                    keyBuilder = serialNumber
                    IOObjectRelease(platformExpert)
                }
            #endif
            return makeEngine(key: keyBuilder + keyBuilder + keyBuilder)
        #else
            let keychainServiceID = "wiki.qaq.rayon.kcAccess"
            let masterKeyID = "wiki.qaq.rayon.MasterCrypto"
            let keychain = Keychain(service: keychainServiceID)
            var key: String?
            for _ in 0 ..< 3 where key == nil {
                do {
                    if let master = try keychain.getString(masterKeyID), master.count > 2 {
                        key = master
                    } else {
                        try keychain.remove(masterKeyID)
                        let new = UUID().uuidString
                        // Persist before activating: assigning the key ahead of
                        // a successful write would encrypt data under a key that
                        // is lost on the next launch.
                        try keychain
                            .label("Rayon Master Crypto Key")
                            .comment("Rayon requires a master crypto key to access your encrypted data on disk and protects your accounts")
                            .set(new, key: masterKeyID)
                        key = new
                    }
                } catch {
                    debugPrint("AES: keychain access failed: \(error.localizedDescription)")
                }
            }
            guard let key = key else {
                // Without the persisted key, previously stored data is
                // unreadable either way; crashing would also take the app
                // down. Stay usable with an ephemeral key; data saved in
                // this state will not survive a restart.
                debugPrint("AES: no persisted master key, falling back to an ephemeral key")
                return makeEngine(key: UUID().uuidString)
            }
            return makeEngine(key: key)
        #endif
    }()

    /// Builds an engine whose key doubles as IV. The initializer pads inputs
    /// to the required sizes, so any string of 16+ characters succeeds.
    private static func makeEngine(key: String) -> AES {
        guard let engine = AES(key: key, iv: key) else {
            preconditionFailure("unreachable: key length is sufficient")
        }
        return engine
    }

    /// 初始化 AES 引擎
    /// - Parameters:
    ///   - initKey: 要求足够长 大于或等于 32
    ///   - initIV: 要求足够长 大于或等于 16
    internal init?(key initKey: String, iv initIV: String) {
        // 初始化密钥 核查长度要求
        if initKey.count < kCCKeySizeAES128 || initIV.count < kCCBlockSizeAES128 {
            return nil
        }
        // 修改 key 到指定长度
        var initKey = initKey
        while initKey.count < 32 { // 防止意外
            initKey += initKey
        }
        while initKey.count > 32 {
            initKey.removeLast()
        }
        guard initKey.count == kCCKeySizeAES128 || initKey.count == kCCKeySizeAES256,
              let keyData = initKey.data(using: .utf8)
        else {
            return nil
        }
        // 修改 iv 到指定长度
        var initIV = initIV
        while initIV.count < kCCBlockSizeAES128 { // 防止意外
            initIV += initIV
        }
        while initIV.count > kCCBlockSizeAES128 {
            initIV.removeLast()
        }
        guard initIV.count == kCCBlockSizeAES128, let ivData = initIV.data(using: .utf8) else {
            debugPrint("Error \(#file) \(#line): Failed to set an initial vector.")
            return nil
        }
        // 储存
        key = keyData
        iv = ivData
    }

    // MARK: - API

    public func encrypt(data: Data) -> Data? {
        crypt(data: data, option: CCOperation(kCCEncrypt))
    }

    public func decrypt(data: Data) -> Data? {
        crypt(data: data, option: CCOperation(kCCDecrypt))
    }

    // MARK: - INTERNAL

    private func crypt(data: Data, option: CCOperation) -> Data? {
        let cryptLength = data.count + kCCBlockSizeAES128
        var cryptData = Data(count: cryptLength)

        let keyLength = key.count
        let options = CCOptions(kCCOptionPKCS7Padding)

        var bytesLength = Int(0)

        let status = cryptData.withUnsafeMutableBytes { cryptBytes in
            data.withUnsafeBytes { dataBytes in
                iv.withUnsafeBytes { ivBytes in
                    key.withUnsafeBytes { keyBytes in
                        CCCrypt(option, CCAlgorithm(kCCAlgorithmAES), options, keyBytes.baseAddress, keyLength, ivBytes.baseAddress, dataBytes.baseAddress, data.count, cryptBytes.baseAddress, cryptLength, &bytesLength)
                    }
                }
            }
        }

        guard UInt32(status) == UInt32(kCCSuccess) else {
            debugPrint("Error: Failed to crypt data. Status \(status)")
            return nil
        }

        cryptData.removeSubrange(bytesLength ..< cryptData.count)
        return cryptData
    }
}
