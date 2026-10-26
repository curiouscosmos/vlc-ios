/*****************************************************************************
 * DiscourseSearchResults.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * Accumulator for the two result lists of a search. The API paginates
 * `/discourses` and `/discourse-audios` independently, so a page is appended for
 * both at once, deduped by id, and "has more" follows whichever list is deeper.
 *****************************************************************************/

import Foundation

struct DiscourseSearchResults {
    private(set) var discourses: [Discourse] = []
    private(set) var tracks: [DiscourseAudio] = []
    private(set) var page = 0
    private(set) var totalPages = 0

    var isEmpty: Bool {
        discourses.isEmpty && tracks.isEmpty
    }

    var hasMore: Bool {
        page > 0 && page < totalPages
    }

    mutating func reset() {
        discourses = []
        tracks = []
        page = 0
        totalPages = 0
    }

    /// Appends one page of each result type, skipping ids already rendered (a
    /// page can overlap the previous one when the catalogue changes mid-scroll).
    mutating func append(discourses pageOfDiscourses: DiscoursePage<Discourse>,
                         tracks pageOfTracks: DiscoursePage<DiscourseAudio>) {
        var knownDiscourses = Set(discourses.map(\.id))
        for discourse in pageOfDiscourses.data where !knownDiscourses.contains(discourse.id) {
            knownDiscourses.insert(discourse.id)
            discourses.append(discourse)
        }

        var knownTracks = Set(tracks.map(\.id))
        for track in pageOfTracks.data where !knownTracks.contains(track.id) {
            knownTracks.insert(track.id)
            tracks.append(track)
        }

        page = max(page, pageOfDiscourses.meta.page, pageOfTracks.meta.page)
        totalPages = max(totalPages, pageOfDiscourses.meta.totalPages, pageOfTracks.meta.totalPages)
    }
}
