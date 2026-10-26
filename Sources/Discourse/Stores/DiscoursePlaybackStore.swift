/*****************************************************************************
 * DiscoursePlaybackStore.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * Per-track resume points, completion and the manually marked "played" flag,
 * plus the track index needed to turn those into a progress ring for a
 * discourse card.
 *
 * Android keeps one key per track (`osho_progress_member.<id>`,
 * `osho_progress_duration.<id>`); iOS keeps the same information in one JSON
 * index (`osho_api_discourse_track_info`) and the documented
 * `osho_api_discourse_playback_position.<audioId>` keys for positions.
 *****************************************************************************/

import Foundation

final class DiscoursePlaybackStore {
    struct TrackInfo: Codable, Hashable {
        let discourseID: String
        let durationMilliseconds: Double
    }

    enum Keys {
        static let positionPrefix = "osho_api_discourse_playback_position."
        static let played = "osho_api_discourse_played_audios"
        static let completed = "osho_api_discourse_completed_audios"
        static let trackInfo = "osho_api_discourse_track_info"
    }

    /// `userInfo` key of the changed audio id on the progress notification.
    static let audioIDKey = "audioID"

    static let shared = DiscoursePlaybackStore()

    private let settings: DiscourseSettings
    private let notificationCenter: NotificationCenter
    private let queue = DispatchQueue(label: "online.sandalbar.rajneesh-discourse.playback")

    init(settings: DiscourseSettings = .shared,
         notificationCenter: NotificationCenter = .default) {
        self.settings = settings
        self.notificationCenter = notificationCenter
    }

    // MARK: - Track index

    /// Registers every track of a discourse so the card can show a progress
    /// ring. Tracks that disappeared from the discourse are dropped.
    func register(_ tracks: [DiscourseAudio], discourseID: String? = nil) {
        queue.sync {
            var index = trackIndex()

            if let discourseID {
                let currentIDs = Set(tracks.map(\.id))
                for (id, info) in index where info.discourseID == discourseID && !currentIDs.contains(id) {
                    index.removeValue(forKey: id)
                }
            }

            for track in tracks {
                let duration = track.durationMilliseconds.map { Double($0) } ?? 0
                let id = track.id
                if let existing = index[id],
                   existing.discourseID == track.discourseID,
                   duration <= 0 || existing.durationMilliseconds == duration {
                    continue
                }
                let resolvedDuration = duration > 0
                    ? duration
                    : index[id]?.durationMilliseconds ?? 0
                index[id] = TrackInfo(discourseID: track.discourseID, durationMilliseconds: resolvedDuration)
            }

            saveTrackIndex(index)
        }
        postChange(audioID: nil)
    }

    func register(id: String, discourseID: String, durationMilliseconds: Double) {
        queue.sync {
            var index = trackIndex()
            let resolved = durationMilliseconds > 0
                ? durationMilliseconds
                : index[id]?.durationMilliseconds ?? 0
            if let existing = index[id],
               existing.discourseID == discourseID,
               existing.durationMilliseconds == resolved {
                return
            }
            index[id] = TrackInfo(discourseID: discourseID, durationMilliseconds: resolved)
            saveTrackIndex(index)
        }
        postChange(audioID: id)
    }

    func trackInfo(for audioID: String) -> TrackInfo? {
        queue.sync { trackIndex()[audioID] }
    }

    // MARK: - Positions

    func position(audioID: String) -> Double? {
        queue.sync { positionLocked(audioID: audioID) }
    }

    /// Stores a resume point in milliseconds. A position at the very start also
    /// clears the completed flag, so replaying a finished track starts over.
    func savePosition(_ position: Double, audioID: String) {
        let clamped = max(0, position)
        queue.sync {
            settings.set(clamped, forKey: Keys.positionPrefix + audioID)
            if clamped < 1_000 {
                var completed = completedIDs()
                if completed.remove(audioID) != nil {
                    saveCompleted(completed)
                }
            }
        }
        postChange(audioID: audioID)
    }

    /// Clears the resume point and the completed flag (reset / replay from start).
    func clearProgress(audioID: String) {
        queue.sync {
            settings.remove(Keys.positionPrefix + audioID)
            var completed = completedIDs()
            if completed.remove(audioID) != nil {
                saveCompleted(completed)
            }
        }
        postChange(audioID: audioID)
    }

    /// Called when the player reaches the end of the track.
    func markCompleted(audioID: String) {
        queue.sync {
            var completed = completedIDs()
            guard completed.insert(audioID).inserted else {
                return
            }
            saveCompleted(completed)
        }
        postChange(audioID: audioID)
    }

    func isCompleted(audioID: String) -> Bool {
        queue.sync { completedIDs().contains(audioID) }
    }

    /// 0…1 progress of a single track, `1` when it completed.
    func fraction(audioID: String) -> Double {
        queue.sync { fractionLocked(audioID: audioID) }
    }

    /// 0…1 progress of a discourse: the sum of its known track fractions divided
    /// by the track count (the catalogue's `total_tracks` when available).
    func discourseFraction(discourseID: String, trackCount: Int? = nil) -> Double {
        queue.sync {
            let index = trackIndex()
            let tracks = index.filter { $0.value.discourseID == discourseID }
            let count = max(trackCount ?? tracks.count, 1)
            let sum = tracks.keys.reduce(0.0) { $0 + fractionLocked(audioID: $1) }
            return min(max(sum / Double(count), 0), 1)
        }
    }

    // MARK: - Manually marked as played

    func isPlayed(audioID: String) -> Bool {
        queue.sync { playedIDs().contains(audioID) }
    }

    func markPlayed(audioID: String) {
        queue.sync {
            var played = playedIDs()
            guard played.insert(audioID).inserted else {
                return
            }
            settings.set(played, forKey: Keys.played)
        }
        postChange(audioID: audioID)
    }

    func clearPlayed(audioID: String) {
        queue.sync {
            var played = playedIDs()
            guard played.remove(audioID) != nil else {
                return
            }
            settings.set(played, forKey: Keys.played)
        }
        postChange(audioID: audioID)
    }

    func removeAll() {
        queue.sync {
            let index = trackIndex()
            for id in index.keys {
                settings.remove(Keys.positionPrefix + id)
            }
            settings.remove(Keys.trackInfo)
            settings.remove(Keys.played)
            settings.remove(Keys.completed)
        }
        postChange(audioID: nil)
    }

    // MARK: - Internals

    private func fractionLocked(audioID: String) -> Double {
        if completedIDs().contains(audioID) {
            return 1
        }
        let duration = trackIndex()[audioID]?.durationMilliseconds ?? 0
        guard duration > 0, let position = positionLocked(audioID: audioID) else {
            return 0
        }
        return min(max(position / duration, 0), 1)
    }

    private func positionLocked(audioID: String) -> Double? {
        guard let position = settings.double(Keys.positionPrefix + audioID), position >= 0 else {
            return nil
        }
        return position
    }

    private func trackIndex() -> [String: TrackInfo] {
        settings.decode([String: TrackInfo].self, forKey: Keys.trackInfo) ?? [:]
    }

    private func saveTrackIndex(_ index: [String: TrackInfo]) {
        if index.isEmpty {
            settings.remove(Keys.trackInfo)
        } else {
            settings.encode(index, forKey: Keys.trackInfo)
        }
    }

    private func completedIDs() -> Set<String> {
        settings.stringSet(Keys.completed)
    }

    private func saveCompleted(_ ids: Set<String>) {
        if ids.isEmpty {
            settings.remove(Keys.completed)
        } else {
            settings.set(ids, forKey: Keys.completed)
        }
    }

    private func playedIDs() -> Set<String> {
        settings.stringSet(Keys.played)
    }

    private func postChange(audioID: String?) {
        var userInfo: [AnyHashable: Any]?
        if let audioID {
            userInfo = [Self.audioIDKey: audioID]
        }
        let notificationCenter = self.notificationCenter
        let post = {
            notificationCenter.post(name: .discoursePlaybackProgressDidChange,
                                    object: self,
                                    userInfo: userInfo)
        }
        if Thread.isMainThread {
            post()
        } else {
            DispatchQueue.main.async(execute: post)
        }
    }
}
