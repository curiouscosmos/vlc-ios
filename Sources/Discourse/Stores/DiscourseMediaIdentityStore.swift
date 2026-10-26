/*****************************************************************************
 * DiscourseMediaIdentityStore.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * A discourse queue is a list of plain `VLCMedia` objects, and the app restores
 * the last queue from an `.m3u` on launch, which drops every custom attribute.
 * The identity therefore travels in two places: the media's libvlc "meta extra"
 * (fast, lives with the object) and this small URL index (durable, survives the
 * queue being serialised and rebuilt). Phase 10 uses it to attribute progress,
 * stats and history to the right track.
 *****************************************************************************/

import Foundation

/// Which discourse track a player item represents.
struct DiscourseMediaIdentity: Codable, Hashable {
    let discourseID: String
    let audioID: String

    /// Keys of the libvlc meta extras written on every discourse media.
    static let discourseExtraKey = "rd.discourseID"
    static let audioExtraKey = "rd.audioID"
}

/// Bounded, durable map from an audio URL to its discourse identity.
final class DiscourseMediaIdentityStore {
    static let shared = DiscourseMediaIdentityStore()
    /// `UserDefaults` key, see the persistence contract in AGENTS.md section 7.
    static let settingsKey = "osho_api_discourse_media_identity"

    private struct Entry: Codable {
        let discourseID: String
        let audioID: String
        let recordedAt: Double
    }

    private let settings: DiscourseSettings
    private let now: () -> Date
    private let limit: Int
    private let queue = DispatchQueue(label: "online.sandalbar.discourse.media-identity")

    /// - Parameters:
    ///   - settings: defaults wrapper; tests inject their own suite.
    ///   - now: clock used for eviction, injectable for tests.
    ///   - limit: how many URLs are remembered before the oldest are dropped.
    init(settings: DiscourseSettings = .shared,
         now: @escaping () -> Date = Date.init,
         limit: Int = 512) {
        self.settings = settings
        self.now = now
        self.limit = max(1, limit)
    }

    /// Remembers which track lives behind `url`, replacing any older record.
    func record(url: URL, identity: DiscourseMediaIdentity) {
        queue.sync {
            var entries = loadEntries()
            entries[url.absoluteString] = Entry(discourseID: identity.discourseID,
                                                audioID: identity.audioID,
                                                recordedAt: now().timeIntervalSince1970)
            storeEntries(entries)
        }
    }

    /// Looks the identity up again after the queue was rebuilt from a playlist.
    func identity(for url: URL) -> DiscourseMediaIdentity? {
        queue.sync {
            guard let entry = loadEntries()[url.absoluteString] else {
                return nil
            }
            return DiscourseMediaIdentity(discourseID: entry.discourseID,
                                          audioID: entry.audioID)
        }
    }

    func reset() {
        queue.sync {
            settings.remove(Self.settingsKey)
        }
    }

    // MARK: - Storage

    private func loadEntries() -> [String: Entry] {
        settings.decode([String: Entry].self, forKey: Self.settingsKey) ?? [:]
    }

    private func storeEntries(_ entries: [String: Entry]) {
        var entries = entries
        if entries.count > limit {
            let overflow = entries.count - limit
            let oldest = entries.sorted { $0.value.recordedAt < $1.value.recordedAt }.prefix(overflow)
            for key in oldest.map(\.key) {
                entries.removeValue(forKey: key)
            }
        }
        settings.encode(entries, forKey: Self.settingsKey)
    }
}
