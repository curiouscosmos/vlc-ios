/*****************************************************************************
 * DiscoursePlayback.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * The one place that turns catalogue tracks into an upstream playback queue.
 * It reuses `VLCPlaybackService.playMediaList(_:firstIndex:)` and the shared
 * `VLCMediaList`, so lock-screen controls, background audio, the mini player and
 * the queue screen behave exactly as they do for local media.
 *
 * Starting a single known track (search, home, deep links) starts a one-item
 * queue immediately and appends the rest of the discourse once the track list
 * arrives, without interrupting playback (AGENTS.md 6.3).
 *****************************************************************************/

import Foundation

@MainActor
final class DiscoursePlayback {
    static let shared = DiscoursePlayback()

    /// The discourse currently queued, and its tracks in queue order.
    struct Context {
        let discourse: Discourse?
        var tracks: [DiscourseAudio]
    }

    private let playbackService: PlaybackService
    private let client: DiscourseAPIClient
    private let identityStore: DiscourseMediaIdentityStore
    private let playbackStore: DiscoursePlaybackStore
    private let registry: DiscourseTrackRegistry

    private(set) var context: Context?

    init(playbackService: PlaybackService = .sharedInstance(),
         client: DiscourseAPIClient = .shared,
         identityStore: DiscourseMediaIdentityStore = .shared,
         playbackStore: DiscoursePlaybackStore = .shared,
         registry: DiscourseTrackRegistry = .shared) {
        self.playbackService = playbackService
        self.client = client
        self.identityStore = identityStore
        self.playbackStore = playbackStore
        self.registry = registry
    }

    // MARK: - Starting playback

    /// Plays `tracks` as the queue, starting at `index`. Returns `false` when no
    /// track had a usable URL.
    @discardableResult
    func play(tracks: [DiscourseAudio], discourse: Discourse?, startingAt index: Int) -> Bool {
        guard let queue = DiscourseMediaFactory.mediaList(for: tracks,
                                                          discourse: discourse,
                                                          startingAt: index,
                                                          identityStore: identityStore) else {
            return false
        }

        for offset in 0..<queue.mediaList.count {
            queue.mediaList.media(at: UInt(offset))?.addOptions(playbackService.mediaOptionsDictionary)
        }

        register(queue.tracks, discourse: discourse)

        // Resume the item playback starts at; later items start at the
        // beginning ("AGENTS 6.3"). Negative enforces no start position.
        let startingTrack = queue.tracks.indices.contains(queue.firstIndex)
            ? queue.tracks[queue.firstIndex]
            : nil
        playbackService.startPosition = startPositionFraction(for: startingTrack) ?? -1

        context = Context(discourse: discourse, tracks: queue.tracks)
        playbackService.playMediaList(queue.mediaList,
                                      firstIndex: queue.firstIndex,
                                      subtitlesFilePath: nil)
        return true
    }

    /// Starts a queue that only knows `track`, then extends it with the rest of
    /// the discourse once the track list is available. Used by entry points that
    /// have a single track at hand (search results, recently played).
    @discardableResult
    func play(track: DiscourseAudio, discourse: Discourse?) -> Bool {
        guard play(tracks: [track], discourse: discourse, startingAt: 0) else {
            return false
        }
        extendQueueWithDiscourse(of: track, discourse: discourse)
        return true
    }

    // MARK: - Track actions

    /// Inserts `track` right after the item being played.
    func playNext(_ track: DiscourseAudio, discourse: Discourse?) {
        guard let media = makeQueuedMedia(for: track, discourse: discourse) else {
            return
        }
        let list = playbackService.mediaList
        guard !list.isEmpty,
              let current = playbackService.currentlyPlayingMedia else {
            _ = play(track: track, discourse: discourse)
            return
        }

        let currentIndex = position(of: current, in: list)
        if currentIndex >= 0 {
            list.insert(media, at: UInt(currentIndex + 1))
        } else {
            _ = list.add(media)
        }

        let shuffled = playbackService.shuffledList
        if !shuffled.isEmpty {
            let shuffledIndex = position(of: current, in: shuffled)
            if shuffledIndex >= 0 {
                shuffled.insert(media, at: UInt(shuffledIndex + 1))
            } else {
                _ = shuffled.add(media)
            }
        }
    }

    /// Appends `track` to the end of the current queue.
    func appendToQueue(_ track: DiscourseAudio, discourse: Discourse?) {
        guard let media = makeQueuedMedia(for: track, discourse: discourse) else {
            return
        }
        let list = playbackService.mediaList
        guard !list.isEmpty else {
            _ = play(track: track, discourse: discourse)
            return
        }

        _ = list.add(media)
        _ = playbackService.shuffledList.add(media)
    }

    // MARK: - Current item

    /// Identity of the item the player is on, or `nil` for non-discourse media.
    func currentIdentity() -> DiscourseMediaIdentity? {
        guard let media = playbackService.currentlyPlayingMedia else {
            return nil
        }
        return DiscourseMediaFactory.identity(of: media, identityStore: identityStore)
    }

    // MARK: - Queue continuation

    private func extendQueueWithDiscourse(of track: DiscourseAudio, discourse: Discourse?) {
        let discourseID = (discourse?.id ?? track.discourseID).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !discourseID.isEmpty else {
            return
        }

        let startedList = playbackService.mediaList

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            let fetched = try? await self.client.discourseTracks(discourseID: discourseID)
            guard let tracks = fetched, tracks.count > 1 else {
                return
            }
            // The user may have started something else while we were loading.
            guard self.playbackService.mediaList === startedList else {
                return
            }
            self.appendRemainingTracks(tracks, to: startedList, discourse: discourse)
        }
    }

    private func appendRemainingTracks(_ tracks: [DiscourseAudio],
                                       to mediaList: VLCMediaList,
                                       discourse: Discourse?) {
        let known = Set((0..<mediaList.count)
            .compactMap { mediaList.media(at: UInt($0)) }
            .compactMap { DiscourseMediaFactory.identity(of: $0, identityStore: identityStore)?.audioID })

        var appended: [DiscourseAudio] = []
        for (offset, track) in tracks.enumerated() where !known.contains(track.id) {
            guard let media = DiscourseMediaFactory.media(for: track,
                                                          discourse: discourse,
                                                          fallbackTrackNumber: offset + 1,
                                                          identityStore: identityStore) else {
                continue
            }
            media.addOptions(playbackService.mediaOptionsDictionary)
            _ = mediaList.add(media)
            _ = playbackService.shuffledList.add(media)
            appended.append(track)
        }

        if !appended.isEmpty {
            context?.tracks.append(contentsOf: appended)
            register(appended, discourse: discourse)
        }
    }

    // MARK: - Helpers

    /// Keeps the progress index (durations for the rings) and the payload
    /// registry (history needs the full track after 60 s) in step with the queue.
    private func register(_ tracks: [DiscourseAudio], discourse: Discourse?) {
        guard !tracks.isEmpty else {
            return
        }
        playbackStore.register(tracks, discourseID: discourse?.id ?? tracks.first?.discourseID)
        registry.register(tracks: tracks, discourse: discourse)
    }

    private func startPositionFraction(for track: DiscourseAudio?) -> Float? {
        guard let track else {
            return nil
        }
        let duration = track.durationMilliseconds.map { Double($0) }
            ?? playbackStore.trackInfo(for: track.id)?.durationMilliseconds
            ?? 0
        return DiscoursePlaybackResume.fraction(
            durationMilliseconds: duration,
            positionMilliseconds: playbackStore.position(audioID: track.id),
            completed: playbackStore.isCompleted(audioID: track.id))
    }

    private func makeQueuedMedia(for track: DiscourseAudio, discourse: Discourse?) -> VLCMedia? {
        guard let media = DiscourseMediaFactory.media(for: track,
                                                      discourse: discourse,
                                                      fallbackTrackNumber: track.trackNumber ?? 0,
                                                      identityStore: identityStore) else {
            return nil
        }
        media.addOptions(playbackService.mediaOptionsDictionary)
        register([track], discourse: discourse)
        return media
    }

    private func position(of media: VLCMedia, in list: VLCMediaList) -> Int {
        for index in 0..<list.count where list.media(at: UInt(index)) === media {
            return index
        }
        return -1
    }
}
