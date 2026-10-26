/*****************************************************************************
 * DiscoursePlaybackProgress.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * The playback rules of AGENTS.md 6.3, without a player: accumulate actual
 * playback time (position deltas while playing, so pauses, buffering and seeks
 * are excluded), qualify a play after 60 seconds, save the resume point every
 * 30 seconds, save on demand (pause, stop, next, background) and complete a
 * track at its end. Discourses are attributed through their identity, so a
 * single rule set covers every entry point.
 *
 * `DiscoursePlaybackTracker` feeds this type from `VLCPlaybackService`
 * notifications and applies the returned effects to the stores and the API.
 *****************************************************************************/

import Foundation

struct DiscoursePlaybackProgress {
    /// A play counts for the listening stats and the history after 60 seconds of
    /// real playback.
    static let qualificationThreshold: Double = 60_000
    /// The resume point is persisted every 30 seconds of real playback.
    static let saveInterval: Double = 30_000
    /// Position jumps larger than this are seeks, not playback, and never count
    /// toward the qualification.
    static let maximumTickDelta: Double = 3_000
    /// A track within this distance of its end counts as completed.
    static let completionTolerance: Double = 1_000

    enum Effect: Equatable {
        case savePosition(audioID: String, positionMilliseconds: Double)
        case complete(audioID: String)
        case qualify(audioID: String, discourseID: String)
    }

    struct Session: Equatable {
        let audioID: String
        let discourseID: String
        var durationMilliseconds: Double
        var accumulatedMilliseconds: Double = 0
        var lastPositionMilliseconds: Double
        var lastSavedMilliseconds: Double = 0
        var qualified = false
        /// Set once the end was reached, until the user replays from the start.
        var finished = false
    }

    private(set) var session: Session?

    /// Starts tracking a new player item. `startPositionMilliseconds` is where
    /// the player actually started (the resume point, or 0).
    mutating func begin(audioID: String,
                        discourseID: String,
                        durationMilliseconds: Double,
                        startPositionMilliseconds: Double) {
        session = Session(audioID: audioID,
                          discourseID: discourseID,
                          durationMilliseconds: max(0, durationMilliseconds),
                          lastPositionMilliseconds: max(0, startPositionMilliseconds))
    }

    /// Consumes one position sample. `isPlaying` must be false while paused,
    /// buffering or stopped.
    mutating func tick(positionMilliseconds: Double,
                       durationMilliseconds: Double,
                       isPlaying: Bool) -> [Effect] {
        guard var current = session else {
            return []
        }

        if durationMilliseconds > 0 {
            current.durationMilliseconds = durationMilliseconds
        }

        let position = max(0, positionMilliseconds)

        if current.finished {
            // Replaying a finished track from its start arms a new play; the
            // completed flag is cleared by the tracker when the item begins at
            // zero, and the store's resume point is cleared with it.
            if position < max(current.durationMilliseconds / 2, 1_000) {
                session = Session(audioID: current.audioID,
                                  discourseID: current.discourseID,
                                  durationMilliseconds: current.durationMilliseconds,
                                  lastPositionMilliseconds: position)
            } else {
                session = current
            }
            return []
        }

        var effects: [Effect] = []

        let delta = position - current.lastPositionMilliseconds
        if isPlaying, delta > 0, delta <= Self.maximumTickDelta {
            current.accumulatedMilliseconds += delta
        }
        current.lastPositionMilliseconds = position

        if !current.qualified, current.accumulatedMilliseconds >= Self.qualificationThreshold {
            current.qualified = true
            effects.append(.qualify(audioID: current.audioID, discourseID: current.discourseID))
        }

        if current.durationMilliseconds > 0,
           position >= current.durationMilliseconds - Self.completionTolerance {
            current.finished = true
            effects.append(.complete(audioID: current.audioID))
        } else if position > 0,
                  current.accumulatedMilliseconds - current.lastSavedMilliseconds >= Self.saveInterval {
            current.lastSavedMilliseconds = current.accumulatedMilliseconds
            effects.append(.savePosition(audioID: current.audioID,
                                         positionMilliseconds: position))
        }

        session = current
        return effects
    }

    /// Persists the current position on pause, stop, next item, failure or when
    /// the app goes to the background.
    mutating func flush() -> [Effect] {
        guard let current = session, !current.finished, current.lastPositionMilliseconds > 0 else {
            return []
        }
        return [.savePosition(audioID: current.audioID,
                              positionMilliseconds: current.lastPositionMilliseconds)]
    }

    /// Stops tracking; the next item starts a new session.
    mutating func end() {
        session = nil
    }
}

/// Turns the stored resume point into the `VLCPlaybackService.startPosition`
/// fraction the upstream player expects.
enum DiscoursePlaybackResume {
    /// Positions below a second are not worth resuming.
    static let minimumPositionMilliseconds: Double = 1_000
    /// Do not resume into the last few seconds of a track.
    static let tailMarginMilliseconds: Double = 5_000
    /// `VLCPlaybackService.startPosition` is a 0…1 fraction.
    static let maximumFraction: Float = 0.98

    static func fraction(durationMilliseconds: Double,
                         positionMilliseconds: Double?,
                         completed: Bool) -> Float? {
        guard !completed,
              let position = positionMilliseconds,
              durationMilliseconds > 0,
              position >= minimumPositionMilliseconds,
              position < durationMilliseconds - tailMarginMilliseconds else {
            return nil
        }
        return min(Float(position / durationMilliseconds), maximumFraction)
    }
}
