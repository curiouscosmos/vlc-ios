/*****************************************************************************
 * DiscourseIdentity.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * The backend has no accounts. Every install generates one anonymous UUID and
 * sends it with likes and listening stats. The durable copy lives in the
 * keychain (same mechanism as the passcode, via XKKeychain); a mirror in
 * UserDefaults keeps reads cheap and survives a keychain hiccup.
 *
 * The UUID is an identifier, not a credential. It is never logged.
 *****************************************************************************/

import Foundation

final class DiscourseIdentity {
    static let shared = DiscourseIdentity()

    /// UserDefaults mirror, named after the Android reference implementation.
    static let userDefaultsKey = "osho_api_user_id"
    /// Keychain service holding the durable copy.
    static let keychainService = "online.sandalbar.rajneesh-discourse.identity"

    private let lock = NSLock()
    private let defaults: UserDefaults
    private let keychain: DiscourseIdentityKeychain

    init(defaults: UserDefaults = .standard,
         keychain: DiscourseIdentityKeychain = DiscourseIdentityKeychain(service: DiscourseIdentity.keychainService)) {
        self.defaults = defaults
        self.keychain = keychain
    }

    /// The anonymous identity of this install, generated on first use.
    var userID: String {
        lock.lock()
        defer { lock.unlock() }
        return resolveUserIDLocked()
    }

    /// The identity if it already exists, without generating a new one.
    var existingUserID: String? {
        lock.lock()
        defer { lock.unlock() }
        return storedUserID()
    }

    /// Generates a fresh identity. Intended for a future "reset my data" action.
    @discardableResult
    func reset() -> String {
        lock.lock()
        defer { lock.unlock() }
        keychain.remove()
        defaults.removeObject(forKey: Self.userDefaultsKey)
        let newID = UUID().uuidString.lowercased()
        persist(newID)
        return newID
    }

    // MARK: - Internals

    private func resolveUserIDLocked() -> String {
        if let existing = storedUserID() {
            return existing
        }
        let newID = UUID().uuidString.lowercased()
        persist(newID)
        return newID
    }

    private func storedUserID() -> String? {
        if let fromKeychain = keychain.read(), Self.isUUID(fromKeychain) {
            mirrorToDefaults(fromKeychain)
            return fromKeychain.lowercased()
        }
        if let fromDefaults = defaults.string(forKey: Self.userDefaultsKey), Self.isUUID(fromDefaults) {
            // Restore the durable copy if it was lost.
            keychain.write(fromDefaults.lowercased())
            return fromDefaults.lowercased()
        }
        return nil
    }

    private func persist(_ userID: String) {
        mirrorToDefaults(userID)
        keychain.write(userID)
    }

    private func mirrorToDefaults(_ userID: String) {
        guard defaults.string(forKey: Self.userDefaultsKey) != userID else {
            return
        }
        defaults.set(userID, forKey: Self.userDefaultsKey)
    }

    static func isUUID(_ value: String) -> Bool {
        UUID(uuidString: value) != nil
    }
}

/// Thin wrapper over XKKeychain so the identity logic stays testable.
struct DiscourseIdentityKeychain {
    let service: String

    func read() -> String? {
        let item = try? XKKeychainGenericPasswordItem(forService: service, account: service)
        return item?.secret.stringValue
    }

    @discardableResult
    func write(_ value: String) -> Bool {
        let item = XKKeychainGenericPasswordItem()
        item.service = service
        item.account = service
        item.secret.stringValue = value
        do {
            try item.save()
            return true
        } catch {
            DiscourseDiagnostics.log("could not persist the anonymous identity in the keychain",
                                     level: .warning,
                                     context: "identity")
            return false
        }
    }

    func remove() {
        do {
            try XKKeychainGenericPasswordItem.removeItems(forService: service)
        } catch {
            DiscourseDiagnostics.log("could not remove the keychain identity: \(error.localizedDescription)",
                                     level: .warning,
                                     context: "identity")
        }
    }
}
