/*****************************************************************************
 * DiscourseLocalTrack.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * Home's *Recently played tracks* merges the discourse history with the device
 * library's own playback history (AGENTS section 6.1). This is the display
 * adapter for a library item: it lifts the title, artwork and duration out of
 * `VLCMLMedia` so the row needs no database access, keeps the media for
 * playback, and identifies the item by its file URL (media identity) so the two
 * histories cannot duplicate a track.
 *****************************************************************************/

import Foundation

struct DiscourseLocalTrack: Hashable {
    /// The media identity: the main file's URL.
    let url: URL
    let title: String
    let subtitle: String?
    let artworkURL: URL?
    let durationSeconds: Double?
    /// The library object, used to start playback. `nil` for display-only items.
    let media: VLCMLMedia?

    init(url: URL,
         title: String,
         subtitle: String?,
         artworkURL: URL?,
         durationSeconds: Double?,
         media: VLCMLMedia?) {
        self.url = url
        self.title = title
        self.subtitle = subtitle
        self.artworkURL = artworkURL
        self.durationSeconds = durationSeconds
        self.media = media
    }

    /// Builds the row model for a library media, or `nil` when the item has no
    /// playable file.
    static func make(from media: VLCMLMedia) -> DiscourseLocalTrack? {
        guard let url = media.mainFile()?.mrl else {
            return nil
        }

        let trimmedTitle = media.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = url.deletingPathExtension().lastPathComponent
        let title = trimmedTitle.isEmpty ? fallback : trimmedTitle

        var parts: [String] = []
        if let artist = media.artist?.name.trimmingCharacters(in: .whitespacesAndNewlines),
           !artist.isEmpty {
            parts.append(artist)
        } else if let album = media.album?.title.trimmingCharacters(in: .whitespacesAndNewlines),
                  !album.isEmpty {
            parts.append(album)
        }
        let milliseconds = media.duration()
        let seconds = milliseconds > 0 ? Double(milliseconds) / 1_000 : nil
        if let duration = DiscourseDurationFormatter.string(forSeconds: seconds) {
            parts.append(duration)
        }

        return DiscourseLocalTrack(url: url,
                                   title: title,
                                   subtitle: parts.isEmpty ? nil : parts.joined(separator: " · "),
                                   artworkURL: media.thumbnail(),
                                   durationSeconds: seconds,
                                   media: media)
    }

    /// Maps a library history list, keeping the library's order and dropping
    /// duplicates (the same file can appear twice in a corrupted history).
    static func list(from media: [VLCMLMedia]) -> [DiscourseLocalTrack] {
        var seen = Set<URL>()
        return media.compactMap { item in
            guard let track = make(from: item),
                  seen.insert(track.url).inserted else {
                return nil
            }
            return track
        }
    }

    /// The media identity used to dedupe the merged Home list.
    static func == (lhs: DiscourseLocalTrack, rhs: DiscourseLocalTrack) -> Bool {
        return lhs.url == rhs.url
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}
