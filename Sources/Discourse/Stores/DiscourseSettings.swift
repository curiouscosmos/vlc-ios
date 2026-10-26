/*****************************************************************************
 * DiscourseSettings.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * Small typed wrapper over `UserDefaults` shared by every discourse store.
 * Keeping JSON handling in one place means a corrupt value is always treated as
 * "no value" instead of crashing a screen (AGENTS.md section 7).
 *****************************************************************************/

import Foundation

struct DiscourseSettings {
    /// The app-wide defaults used by the shipping stores.
    static let shared = DiscourseSettings(defaults: .standard)

    let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    // MARK: - Typed primitives

    func string(_ key: String) -> String? {
        defaults.string(forKey: key)
    }

    func set(_ value: String?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    func double(_ key: String) -> Double? {
        guard defaults.object(forKey: key) != nil else {
            return nil
        }
        return defaults.double(forKey: key)
    }

    func set(_ value: Double, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    func bool(_ key: String) -> Bool {
        defaults.bool(forKey: key)
    }

    func set(_ value: Bool, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    func int(_ key: String) -> Int? {
        guard defaults.object(forKey: key) != nil else {
            return nil
        }
        return defaults.integer(forKey: key)
    }

    func set(_ value: Int, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    // MARK: - Collections

    func stringSet(_ key: String) -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    func set(_ value: Set<String>, forKey key: String) {
        defaults.set(Array(value).sorted(), forKey: key)
    }

    // MARK: - JSON

    func decode<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }

    func encode<Value: Encodable>(_ value: Value, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }

    func remove(_ key: String) {
        defaults.removeObject(forKey: key)
    }

    func contains(_ key: String) -> Bool {
        defaults.object(forKey: key) != nil
    }
}
