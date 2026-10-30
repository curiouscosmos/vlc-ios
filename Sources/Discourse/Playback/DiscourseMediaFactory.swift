/*****************************************************************************
 * DiscourseMediaFactory.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * Maps a catalogue track onto the `VLCMedia` the upstream player consumes, so
 * discourse playback reuses `VLCPlaybackService` and `VLCMediaList` instead of
 * introducing a second playback path. Field mapping follows AGENTS.md 6.3:
 * URL = resolved remote audio (local download once Phase 12 lands), title =
 * track title, artist = Osho, album = discourse name, artwork = discourse
 * thumbnail, track number, duration, and the identity extras used by Phase 10.
 *****************************************************************************/

import Foundation

/// A queue built from catalogue tracks, plus the index playback starts at.
struct DiscourseMediaQueue {
    let mediaList: VLCMediaList
    /// The tracks that made it into the queue, in queue order.
    let tracks: [DiscourseAudio]
    let firstIndex: Int
}

enum DiscourseMediaFactory {
    /// Artist shown for every discourse track.
    static let defaultArtist = "Osho"

    /// Builds the upstream media list for `tracks`, starting at `index`.
    /// Tracks without a usable HTTPS URL are skipped, and `firstIndex` stays
    /// aligned with the requested track even when earlier ones were skipped.
    static func mediaList(for tracks: [DiscourseAudio],
                          discourse: Discourse?,
                          startingAt index: Int,
                          identityStore: DiscourseMediaIdentityStore = .shared,
                          downloads: DiscourseDownloadStore = .shared) -> DiscourseMediaQueue? {
        var queued: [(media: VLCMedia, track: DiscourseAudio)] = []
        for (offset, track) in tracks.enumerated() {
            guard let media = media(for: track,
                                    discourse: discourse,
                                    fallbackTrackNumber: offset + 1,
                                    identityStore: identityStore,
                                    downloads: downloads) else {
                continue
            }
            queued.append((media, track))
        }

        guard !queued.isEmpty else {
            return nil
        }

        let mediaList = VLCMediaList()
        for item in queued {
            _ = mediaList.add(item.media)
        }

        let requestedTrack = tracks.indices.contains(index) ? tracks[index] : tracks.first
        let firstIndex = queued.firstIndex { $0.track.id == requestedTrack?.id } ?? 0
        return DiscourseMediaQueue(mediaList: mediaList,
                                   tracks: queued.map(\.track),
                                   firstIndex: firstIndex)
    }

    /// Builds the player item for `track`, or `nil` when the payload has no
    /// usable HTTPS audio URL.
    ///
    /// - Parameter fallbackTrackNumber: 1-based position used when the payload
    ///   omits `track_number`.
    static func media(for track: DiscourseAudio,
                      discourse: Discourse?,
                      fallbackTrackNumber: Int,
                      identityStore: DiscourseMediaIdentityStore = .shared,
                      downloads: DiscourseDownloadStore = .shared) -> VLCMedia? {
        // A verified download wins over streaming (AGENTS.md section 6.6):
        // `localURL(for:)` only answers when the file exists and is not empty,
        // so a deleted or truncated file falls back to the CDN.
        guard let url = downloads.localURL(for: track.id) ?? track.audioURL,
              let media = VLCMedia(url: url) else {
            return nil
        }

        // The native MP3 demuxer mis-seeks the generic .audio downloads,
        // landing early or at EOF. The bundled FFmpeg demuxer keeps timestamps accurate.
        if url.isFileURL { media.addOption(":demux=avformat") }
        let metadata = media.metaData
        metadata.title = title(for: track, fallbackTrackNumber: fallbackTrackNumber)
        metadata.artist = defaultArtist
        metadata.album = albumName(for: track, discourse: discourse)
        metadata.trackNumber = UInt32(max(0, track.trackNumber ?? fallbackTrackNumber))
        if let artworkURL = artworkURL(for: track, discourse: discourse) {
            metadata.artworkURL = artworkURL
        }
        if let seconds = track.durationSeconds, seconds.isFinite, seconds > 0 {
            media.length = VLCTime(int: Int32((seconds * 1_000).rounded()))
        }

        let identity = self.identity(for: track, discourse: discourse)
        if !identity.audioID.isEmpty {
            metadata.setExtraValue(identity.discourseID, forKey: DiscourseMediaIdentity.discourseExtraKey)
            metadata.setExtraValue(identity.audioID, forKey: DiscourseMediaIdentity.audioExtraKey)
            identityStore.record(url: url, identity: identity)
        }

        return media
    }

    /// Reads the identity back from a player item: the meta extras first, the
    /// durable URL index second (a queue restored from the last-played playlist
    /// has no extras).
    static func identity(of media: VLCMedia,
                         identityStore: DiscourseMediaIdentityStore = .shared) -> DiscourseMediaIdentity? {
        let metadata = media.metaData
        let audioID = metadata.extraValue(forKey: DiscourseMediaIdentity.audioExtraKey) ?? ""
        if !audioID.isEmpty {
            let discourseID = metadata.extraValue(forKey: DiscourseMediaIdentity.discourseExtraKey) ?? ""
            return DiscourseMediaIdentity(discourseID: discourseID, audioID: audioID)
        }

        guard let url = media.url else {
            return nil
        }
        return identityStore.identity(for: url)
    }

    static func identity(for track: DiscourseAudio, discourse: Discourse?) -> DiscourseMediaIdentity {
        let discourseID = (discourse?.id ?? track.discourseID).trimmingCharacters(in: .whitespacesAndNewlines)
        return DiscourseMediaIdentity(discourseID: discourseID, audioID: track.id)
    }

    // MARK: - Field mapping

    private static func title(for track: DiscourseAudio, fallbackTrackNumber: Int) -> String {
        let title = track.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            return title
        }
        return String(format: NSLocalizedString("DISCOURSE_TRACK_FALLBACK_TITLE",
                                                comment: "Title shown when a track has no title"),
                      fallbackTrackNumber)
    }

    private static func albumName(for track: DiscourseAudio, discourse: Discourse?) -> String? {
        if let title = discourse?.title.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        let name = track.discourseName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private static func artworkURL(for track: DiscourseAudio, discourse: Discourse?) -> URL? {
        return track.thumbnailURL ?? DiscourseURLResolver.resolve(discourse?.thumbnailURLString)
    }
}
