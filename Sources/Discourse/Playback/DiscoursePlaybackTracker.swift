/*****************************************************************************
 * DiscoursePlaybackTracker.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * Glue between `VLCPlaybackService` and the discourse stores. It observes the
 * upstream playback notifications, feeds position samples to
 * `DiscoursePlaybackProgress` and applies the resulting effects:
 *
 * - resume points and completion go to `DiscoursePlaybackStore`;
 * - a play that qualified (60 s of real playback) is recorded in
 *   `DiscourseHistoryStore` and reported once per 24 h through `POST /stats`,
 *   but only while the playback-history switch is on.
 *
 * The identity of the playing item comes from the media factory, so restored
 * queues (no meta extras) resolve through the durable URL index as well.
 *****************************************************************************/

import UIKit

@MainActor
final class DiscoursePlaybackTracker {
    static let shared = DiscoursePlaybackTracker()

    private let playbackService: PlaybackService
    private let client: DiscourseAPIClient
    private let playbackStore: DiscoursePlaybackStore
    private let historyStore: DiscourseHistoryStore
    private let statsStore: DiscourseStatsStore
    private let registry: DiscourseTrackRegistry
    private let identityStore: DiscourseMediaIdentityStore
    private let notificationCenter: NotificationCenter
    private let isHistoryEnabled: () -> Bool

    private var progress = DiscoursePlaybackProgress()
    private var isStarted = false
    private var artworkLookups: Set<String> = []

    init(playbackService: PlaybackService = .sharedInstance(),
         client: DiscourseAPIClient = .shared,
         playbackStore: DiscoursePlaybackStore = .shared,
         historyStore: DiscourseHistoryStore = .shared,
         statsStore: DiscourseStatsStore = .shared,
         registry: DiscourseTrackRegistry = .shared,
         identityStore: DiscourseMediaIdentityStore = .shared,
         notificationCenter: NotificationCenter = .default,
         isHistoryEnabled: @escaping () -> Bool = { DiscoursePlaybackSettings.isHistoryEnabled }) {
        self.playbackService = playbackService
        self.client = client
        self.playbackStore = playbackStore
        self.historyStore = historyStore
        self.statsStore = statsStore
        self.registry = registry
        self.identityStore = identityStore
        self.notificationCenter = notificationCenter
        self.isHistoryEnabled = isHistoryEnabled
    }

    // MARK: - Lifecycle

    func start() {
        guard !isStarted else {
            return
        }
        isStarted = true

        notificationCenter.addObserver(self, selector: #selector(downloadsChanged),
                                       name: .discourseDownloadsDidChange, object: nil)
        notificationCenter.addObserver(self, selector: #selector(restoreCurrentTrackArtwork),
                                       name: Notification.Name(VLCPlaybackServicePlaybackMetadataDidChange), object: nil)
        let names = [VLCPlaybackServicePlaybackDidStart,
                     VLCPlaybackServicePlaybackDidPause,
                     VLCPlaybackServicePlaybackWillStop,
                     VLCPlaybackServicePlaybackDidStop,
                     VLCPlaybackServicePlaybackDidFail,
                     VLCPlaybackServicePlaybackDidMoveOnToNextItem,
                     VLCPlaybackServicePlaybackPositionUpdated]
        for name in names {
            notificationCenter.addObserver(self,
                                           selector: #selector(handlePlaybackNotification(_:)),
                                           name: Notification.Name(name),
                                           object: nil)
        }
        restoreCurrentTrackArtwork()

        notificationCenter.addObserver(self,
                                       selector: #selector(saveProgress),
                                       name: UIApplication.willResignActiveNotification,
                                       object: nil)
        notificationCenter.addObserver(self,
                                       selector: #selector(saveProgress),
                                       name: UIApplication.didEnterBackgroundNotification,
                                       object: nil)
    }

    @objc private func downloadsChanged() {
        guard playbackService.isPlaying,
              let current = playbackService.currentlyPlayingMedia,
              current.url?.isFileURL == false,
              let identity = DiscourseMediaFactory.identity(of: current),
              DiscourseDownloadStore.shared.localURL(for: identity.audioID) != nil,
              let track = registry.track(id: identity.audioID),
              let local = DiscourseMediaFactory.media(for: track, discourse: nil, fallbackTrackNumber: 1) else { return }
        local.metaData.title = current.metaData.title
        local.metaData.album = current.metaData.album
        local.addOptions(playbackService.mediaOptionsDictionary)
        playbackService.replacePlaying(local)
    }

    // MARK: - Notifications

    @objc private func handlePlaybackNotification(_ notification: Notification) {
        switch notification.name {
        case Notification.Name(VLCPlaybackServicePlaybackPositionUpdated),
             Notification.Name(VLCPlaybackServicePlaybackDidStart):
            restoreCurrentTrackArtwork()
            tick()
            if notification.name == Notification.Name(VLCPlaybackServicePlaybackDidStart) { downloadsChanged() }
        case Notification.Name(VLCPlaybackServicePlaybackDidPause),
             Notification.Name(VLCPlaybackServicePlaybackWillStop),
             Notification.Name(VLCPlaybackServicePlaybackDidFail):
            saveProgress()
        case Notification.Name(VLCPlaybackServicePlaybackDidStop),
             Notification.Name(VLCPlaybackServicePlaybackDidMoveOnToNextItem):
            saveProgress()
            progress.end()
        default:
            break
        }
    }

    /// Restored media can have no artwork URL in an older playback snapshot,
    /// or a discourse-level fallback URL. Resolve the audio object and use its
    /// own `discourse_thumbnail_url` for the mini player and full player.
    @objc private func restoreCurrentTrackArtwork() {
        guard let media = playbackService.currentlyPlayingMedia,
              let identity = DiscourseMediaFactory.identity(of: media, identityStore: identityStore),
              !identity.audioID.isEmpty,
              !identity.discourseID.isEmpty else { return }

        if let track = registry.track(id: identity.audioID),
           let artworkURL = track.thumbnailURL {
            if media.metaData.artworkURL != artworkURL {
                media.metaData.artworkURL = artworkURL
            }
            return
        }

        let lookupKey = "\(identity.discourseID):\(identity.audioID)"
        guard artworkLookups.insert(lookupKey).inserted else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let tracks = try? await self.client.discourseTracks(discourseID: identity.discourseID),
                  let track = tracks.first(where: { $0.id == identity.audioID }) else { return }
            self.registry.register(tracks: [track])
            guard let current = self.playbackService.currentlyPlayingMedia,
                  DiscourseMediaFactory.identity(of: current, identityStore: self.identityStore)?.audioID == identity.audioID,
                  let artworkURL = track.thumbnailURL else { return }
            if current.metaData.artworkURL != artworkURL {
                current.metaData.artworkURL = artworkURL
            }
        }
    }

    @objc private func saveProgress() {
        apply(progress.flush())
    }

    // MARK: - Sampling

    private func tick() {
        guard let media = playbackService.currentlyPlayingMedia,
              let identity = DiscourseMediaFactory.identity(of: media,
                                                            identityStore: identityStore) else {
            // Not a discourse item (local media, video): persist where the last
            // discourse item stopped and wait for the next one.
            finishSession()
            return
        }

        if progress.session?.audioID != identity.audioID
            || progress.session?.discourseID != identity.discourseID {
            finishSession()
            beginSession(identity)
        }

        let duration = currentDuration()
        let position = currentPosition(duration: duration)
        let effects = progress.tick(positionMilliseconds: position,
                                    durationMilliseconds: duration,
                                    isPlaying: playbackService.isPlaying)
        apply(effects)
    }

    private func beginSession(_ identity: DiscourseMediaIdentity) {
        let duration = effectiveDuration(for: identity)
        let resumePosition = playbackStore.position(audioID: identity.audioID)

        // Replaying a completed track from its start clears the completed flag
        // (AGENTS 6.3: "cleared on reset/replay-from-start").
        if playbackStore.isCompleted(audioID: identity.audioID),
           (resumePosition ?? 0) < DiscoursePlaybackResume.minimumPositionMilliseconds {
            playbackStore.clearProgress(audioID: identity.audioID)
        }

        progress.begin(audioID: identity.audioID,
                       discourseID: identity.discourseID,
                       durationMilliseconds: duration,
                       startPositionMilliseconds: currentPosition(duration: duration))
    }

    private func finishSession() {
        apply(progress.flush())
        progress.end()
    }

    // MARK: - Player values

    private func effectiveDuration(for identity: DiscourseMediaIdentity) -> Double {
        let mediaDuration = playbackService.mediaDuration
        if mediaDuration > 0 {
            return Double(mediaDuration)
        }
        return playbackStore.trackInfo(for: identity.audioID)?.durationMilliseconds ?? 0
    }

    private func currentDuration() -> Double {
        let mediaDuration = playbackService.mediaDuration
        if mediaDuration > 0 {
            return Double(mediaDuration)
        }
        return progress.session?.durationMilliseconds ?? 0
    }

    /// `VLCPlaybackService.playbackPosition` is a 0…1 fraction.
    private func currentPosition(duration: Double) -> Double {
        guard duration > 0 else {
            return 0
        }
        let fraction = Double(playbackService.playbackPosition)
        return min(max(fraction, 0), 1) * duration
    }

    // MARK: - Effects

    private func apply(_ effects: [DiscoursePlaybackProgress.Effect]) {
        for effect in effects {
            switch effect {
            case .savePosition(let audioID, let position):
                playbackStore.savePosition(position, audioID: audioID)
            case .complete(let audioID):
                playbackStore.markCompleted(audioID: audioID)
            case .qualify(let audioID, let discourseID):
                qualify(audioID: audioID, discourseID: discourseID)
            }
        }
    }

    private func qualify(audioID: String, discourseID: String) {
        guard isHistoryEnabled() else {
            return
        }
        let identity = DiscourseMediaIdentity(discourseID: discourseID, audioID: audioID)
        reportStats(identity)
        recordHistory(identity)
    }

    private func reportStats(_ identity: DiscourseMediaIdentity) {
        guard !identity.discourseID.isEmpty,
              !identity.audioID.isEmpty,
              statsStore.shouldSend(audioID: identity.audioID) else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            let result = try? await self.client.recordStats(discourseID: identity.discourseID,
                                                            audioID: identity.audioID)
            if result != nil {
                self.statsStore.markSent(audioID: identity.audioID)
            }
        }
    }

    private func recordHistory(_ identity: DiscourseMediaIdentity) {
        if let track = registry.track(id: identity.audioID) {
            historyStore.record(audio: track)
            if let discourse = registry.discourse(id: track.discourseID)
                ?? registry.discourse(id: identity.discourseID) {
                historyStore.record(discourse: discourse)
            }
            return
        }

        // A queue restored from the last-played playlist has no payload: fetch
        // it once, then record the play.
        guard !identity.discourseID.isEmpty else {
            return
        }
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            guard let tracks = try? await self.client.discourseTracks(discourseID: identity.discourseID),
                  let track = tracks.first(where: { $0.id == identity.audioID }) else {
                return
            }
            self.registry.register(tracks: [track])
            self.playbackStore.register([track])
            guard self.isHistoryEnabled() else {
                return
            }
            self.historyStore.record(audio: track)
        }
    }
}
