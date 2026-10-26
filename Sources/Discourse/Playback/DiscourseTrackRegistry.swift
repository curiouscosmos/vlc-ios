/*****************************************************************************
 * DiscourseTrackRegistry.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * A bounded in-memory map from audio/discourse ids to the catalogue payloads
 * that were used to build the queue. `DiscoursePlayback` registers every track
 * it queues; the playback tracker reads the payload back when a play qualifies
 * 60 seconds later, because that is when the history needs the full
 * `DiscourseAudio` and not just its identity.
 *
 * Nothing is persisted: a queue restored from the last-played playlist has no
 * payload, and the tracker fetches it once from `/discourse-audios` instead.
 *****************************************************************************/

import Foundation

final class DiscourseTrackRegistry {
    static let shared = DiscourseTrackRegistry()

    /// Keeps the most recent tracks/discourses; older ones are evicted.
    static let limit = 256

    private let queue = DispatchQueue(label: "online.sandalbar.rajneesh-discourse.registry")

    private var tracks: [String: DiscourseAudio] = [:]
    private var trackOrder: [String] = []
    private var discourses: [String: Discourse] = [:]
    private var discourseOrder: [String] = []

    init() {}

    func register(tracks newTracks: [DiscourseAudio], discourse: Discourse? = nil) {
        queue.sync {
            for track in newTracks {
                if self.tracks[track.id] == nil {
                    trackOrder.append(track.id)
                }
                tracks[track.id] = track
            }
            trimTracks()

            if let discourse {
                if discourses[discourse.id] == nil {
                    discourseOrder.append(discourse.id)
                }
                discourses[discourse.id] = discourse
                trimDiscourses()
            }
        }
    }

    func track(id: String) -> DiscourseAudio? {
        queue.sync { tracks[id] }
    }

    func discourse(id: String) -> Discourse? {
        queue.sync { discourses[id] }
    }

    func removeAll() {
        queue.sync {
            tracks.removeAll()
            trackOrder.removeAll()
            discourses.removeAll()
            discourseOrder.removeAll()
        }
    }

    // MARK: - Internals

    private func trimTracks() {
        while trackOrder.count > Self.limit {
            let evicted = trackOrder.removeFirst()
            tracks.removeValue(forKey: evicted)
        }
    }

    private func trimDiscourses() {
        while discourseOrder.count > Self.limit {
            let evicted = discourseOrder.removeFirst()
            discourses.removeValue(forKey: evicted)
        }
    }
}
