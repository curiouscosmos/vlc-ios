/*****************************************************************************
 * DiscourseStatsStore.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * Local dedupe for `POST /stats`: one play per track per 24 hours, and only
 * after the play qualified (60 s of real playback). A track is marked as sent
 * only when the server accepted the request, so a failed call is retried on the
 * next qualification.
 *
 * The Android reference keeps this in a separate `osho_api_stats` preferences
 * file; iOS mirrors it in UserDefaults under `osho_api_stats_sent` as
 * `[audioId: timestamp]` (see AGENTS.md section 7).
 *****************************************************************************/

import Foundation

final class DiscourseStatsStore {
    enum Keys {
        static let sent = "osho_api_stats_sent"
    }

    /// A track is reported at most once per day.
    static let retention: TimeInterval = 24 * 60 * 60

    static let shared = DiscourseStatsStore()

    private let settings: DiscourseSettings
    private let queue = DispatchQueue(label: "online.sandalbar.rajneesh-discourse.stats")

    init(settings: DiscourseSettings = .shared) {
        self.settings = settings
    }

    /// True when this track has not been reported in the last 24 hours.
    func shouldSend(audioID: String, now: Date = Date()) -> Bool {
        queue.sync {
            let sent = prunedSent(now: now)
            guard let timestamp = sent[audioID] else {
                return true
            }
            return now.timeIntervalSince1970 - timestamp >= Self.retention
        }
    }

    /// Records a successful report.
    func markSent(audioID: String, at date: Date = Date()) {
        queue.sync {
            var sent = prunedSent(now: date)
            sent[audioID] = date.timeIntervalSince1970
            settings.encode(sent, forKey: Keys.sent)
        }
    }

    /// Removes expired entries. Cheap enough to run on every check.
    func cleanup(now: Date = Date()) {
        queue.sync {
            _ = prunedSent(now: now)
        }
    }

    func removeAll() {
        queue.sync {
            settings.remove(Keys.sent)
        }
    }

    // MARK: - Internals

    private func prunedSent(now: Date) -> [String: Double] {
        let stored = settings.decode([String: Double].self, forKey: Keys.sent) ?? [:]
        let cutoff = now.timeIntervalSince1970 - Self.retention
        let pruned = stored.filter { $0.value > cutoff }
        if pruned.count != stored.count {
            if pruned.isEmpty {
                settings.remove(Keys.sent)
            } else {
                settings.encode(pruned, forKey: Keys.sent)
            }
        }
        return pruned
    }
}
