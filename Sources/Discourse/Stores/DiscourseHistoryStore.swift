/*****************************************************************************
 * DiscourseHistoryStore.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * Recently played discourses and tracks, newest first, capped at 24 entries and
 * deduplicated by id. Both lists back the Home screen and are only recorded when
 * the playback-history setting is on; that check belongs to the caller so the
 * store stays a pure persistence primitive.
 *****************************************************************************/

import Foundation

final class DiscourseHistoryStore {
    enum Keys {
        static let discourses = "osho_api_recently_played_discourses"
        static let audios = "osho_api_recently_played_audios"
    }

    /// The Home screen shows at most this many entries per section.
    static let limit = 24

    static let shared = DiscourseHistoryStore()

    private let settings: DiscourseSettings
    private let notificationCenter: NotificationCenter
    private let queue = DispatchQueue(label: "online.sandalbar.rajneesh-discourse.history")

    init(settings: DiscourseSettings = .shared,
         notificationCenter: NotificationCenter = .default) {
        self.settings = settings
        self.notificationCenter = notificationCenter
    }

    var recentlyPlayedDiscourses: [Discourse] {
        queue.sync {
            settings.decode([Discourse].self, forKey: Keys.discourses) ?? []
        }
    }

    var recentlyPlayedAudios: [DiscourseAudio] {
        queue.sync {
            settings.decode([DiscourseAudio].self, forKey: Keys.audios) ?? []
        }
    }

    /// Moves the discourse to the front, keeping the list deduplicated and capped.
    func record(discourse: Discourse) {
        queue.sync {
            var items = settings.decode([Discourse].self, forKey: Keys.discourses) ?? []
            items.removeAll { $0.id == discourse.id }
            items.insert(discourse, at: 0)
            if items.count > Self.limit {
                items.removeLast(items.count - Self.limit)
            }
            settings.encode(items, forKey: Keys.discourses)
        }
        postChange()
    }

    /// Moves the track to the front, keeping the list deduplicated and capped.
    func record(audio: DiscourseAudio) {
        queue.sync {
            var items = settings.decode([DiscourseAudio].self, forKey: Keys.audios) ?? []
            items.removeAll { $0.id == audio.id }
            items.insert(audio, at: 0)
            if items.count > Self.limit {
                items.removeLast(items.count - Self.limit)
            }
            settings.encode(items, forKey: Keys.audios)
        }
        postChange()
    }

    /// Removes one entry, e.g. when a downloaded track is deleted.
    func removeAudio(id: String) {
        queue.sync {
            var items = settings.decode([DiscourseAudio].self, forKey: Keys.audios) ?? []
            items.removeAll { $0.id == id }
            settings.encode(items, forKey: Keys.audios)
        }
        postChange()
    }

    func removeAll() {
        queue.sync {
            settings.remove(Keys.discourses)
            settings.remove(Keys.audios)
        }
        postChange()
    }

    private func postChange() {
        let notificationCenter = self.notificationCenter
        if Thread.isMainThread {
            notificationCenter.post(name: .discourseHistoryDidChange, object: self)
        } else {
            DispatchQueue.main.async {
                notificationCenter.post(name: .discourseHistoryDidChange, object: self)
            }
        }
    }
}
