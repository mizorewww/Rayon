//
//  DeviceOwner.swift
//  Rayon
//

import LocalAuthentication

/// Asks the device's owner before a secret shows: Face ID or Touch ID, a
/// paired watch, or the device's password.
enum DeviceOwner {
    @MainActor
    static func confirm(_ reason: String) async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            // An iPhone without a passcode has no owner to ask. A Mac always
            // has its login password; one that cannot ask keeps the secret.
            #if os(iOS)
                return true
            #else
                return false
            #endif
        }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}
