/*****************************************************************************
 * DiscourseStatsCache.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * Weekly top lists for the Home screen. The payload is cached for three hours
 * (the API layer already caches raw responses for 24 hours; this cache is what
 * the UI reads and what a force refresh replaces).
 *
 * A failed refresh never blanks the sections: the previous list is returned and
 * the error is swallowed after being logged. Only a failure with no cached copy
 * propagates to the caller.
 *****************************************************************************/

import Foundation

// MARK: - Service seam

/// The stats routes the cache needs. Tests inject a fake.
protocol DiscourseStatsService {
    func fetchDiscourseStats(window: DiscourseStatsWindow, forceRefresh: Bool) async throws -> [Discourse]
    func fetchAudioStats(window: DiscourseStatsWindow, forceRefresh: Bool) async throws -> [DiscourseAudio]
}

extension DiscourseAPIClient: DiscourseStatsService {
    func fetchDiscourseStats(window: DiscourseStatsWindow, forceRefresh: Bool) async throws -> [Discourse] {
        try await discourseStats(dimension: .discourse, window: window, forceRefresh: forceRefresh)
    }

    func fetchAudioStats(window: DiscourseStatsWindow, forceRefresh: Bool) async throws -> [DiscourseAudio] {
        try await audioStats(dimension: .audio, window: window, forceRefresh: forceRefresh)
    }
}

// MARK: - Cache

final class DiscourseStatsCache {
    enum Keys {
        static let discourses = "osho_api_stats_discourses"
        static let audios = "osho_api_stats_audios"
        static let timeSuffix = ".time"
    }

    /// Top lists are re-fetched after three hours.
    static let timeToLive: TimeInterval = 3 * 60 * 60

    static let shared = DiscourseStatsCache()

    private let settings: DiscourseSettings
    private let service: DiscourseStatsService
    private let dateProvider: () -> Date
    private let queue = DispatchQueue(label: "online.sandalbar.rajneesh-discourse.stats-cache")

    init(settings: DiscourseSettings = .shared,
         service: DiscourseStatsService = DiscourseAPIClient.shared,
         dateProvider: @escaping () -> Date = Date.init) {
        self.settings = settings
        self.service = service
        self.dateProvider = dateProvider
    }

    // MARK: - Top discourses

    func discourses(window: DiscourseStatsWindow = .last7Days,
                    forceRefresh: Bool = false) async throws -> [Discourse] {
        guard window == .last7Days else {
            // Other windows are not cached here, so always ask for fresh data
            // instead of accepting the API layer's 24 h copy.
            return try await service.fetchDiscourseStats(window: window, forceRefresh: true)
        }
        if !forceRefresh, isFresh(Keys.discourses), let cached = cachedDiscourses() {
            return cached
        }

        do {
            let fresh = try await service.fetchDiscourseStats(window: window, forceRefresh: true)
            store(fresh, key: Keys.discourses)
            return fresh
        } catch {
            if let cached = cachedDiscourses() {
                DiscourseDiagnostics.log("serving cached top discourses after a failed refresh",
                                         level: .warning,
                                         context: "stats")
                return cached
            }
            throw error
        }
    }

    // MARK: - Top tracks

    func audios(window: DiscourseStatsWindow = .last7Days,
                forceRefresh: Bool = false) async throws -> [DiscourseAudio] {
        guard window == .last7Days else {
            return try await service.fetchAudioStats(window: window, forceRefresh: true)
        }
        if !forceRefresh, isFresh(Keys.audios), let cached = cachedAudios() {
            return cached
        }

        do {
            let fresh = try await service.fetchAudioStats(window: window, forceRefresh: true)
            store(fresh, key: Keys.audios)
            return fresh
        } catch {
            if let cached = cachedAudios() {
                DiscourseDiagnostics.log("serving cached top tracks after a failed refresh",
                                         level: .warning,
                                         context: "stats")
                return cached
            }
            throw error
        }
    }

    var lastDiscoursesRefresh: Date? {
        timestamp(Keys.discourses)
    }

    var lastAudiosRefresh: Date? {
        timestamp(Keys.audios)
    }

    func removeAll() {
        queue.sync {
            settings.remove(Keys.discourses)
            settings.remove(Keys.discourses + Keys.timeSuffix)
            settings.remove(Keys.audios)
            settings.remove(Keys.audios + Keys.timeSuffix)
        }
    }

    // MARK: - Internals

    /// The last cached top discourses, regardless of age, for an immediate
    /// first render before the network revalidates them.
    func cachedDiscourses() -> [Discourse]? {
        queue.sync { settings.decode([Discourse].self, forKey: Keys.discourses) }
    }

    /// The last cached top tracks, regardless of age, for an immediate first
    /// render before the network revalidates them.
    func cachedAudios() -> [DiscourseAudio]? {
        queue.sync { settings.decode([DiscourseAudio].self, forKey: Keys.audios) }
    }

    private func isFresh(_ key: String) -> Bool {
        guard let refreshed = timestamp(key) else {
            return false
        }
        let age = dateProvider().timeIntervalSince(refreshed)
        return age >= 0 && age < Self.timeToLive
    }

    private func timestamp(_ key: String) -> Date? {
        guard let value = settings.double(key + Keys.timeSuffix), value > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: value)
    }

    private func store<Value: Encodable>(_ value: Value, key: String) {
        queue.sync {
            settings.encode(value, forKey: key)
            settings.set(dateProvider().timeIntervalSince1970, forKey: key + Keys.timeSuffix)
        }
    }
}
