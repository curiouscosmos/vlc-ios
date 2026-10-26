/*****************************************************************************
 * DiscourseHomeContent.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * The Home screen's section model and the rule that turns the stores' payloads
 * into it. Kept free of UIKit so the ordering, dedupe and history gating are
 * unit-testable.
 *****************************************************************************/

import Foundation

enum DiscourseHomeSectionKind: CaseIterable {
    case recentlyPlayedDiscourses
    case recentlyPlayedTracks
    case topDiscourses
    case topTracks

    var title: String {
        switch self {
        case .recentlyPlayedDiscourses:
            return NSLocalizedString("HOME_SECTION_RECENT_DISCOURSES",
                                     comment: "Home section: recently played discourses")
        case .recentlyPlayedTracks:
            return NSLocalizedString("HOME_SECTION_RECENT_TRACKS",
                                     comment: "Home section: recently played tracks")
        case .topDiscourses:
            return NSLocalizedString("HOME_SECTION_TOP_DISCOURSES",
                                     comment: "Home section: top discourses this week")
        case .topTracks:
            return NSLocalizedString("HOME_SECTION_TOP_TRACKS",
                                     comment: "Home section: top tracks this week")
        }
    }

    /// Discourses scroll horizontally as cards; tracks are full-width rows.
    var isCarousel: Bool {
        self == .recentlyPlayedDiscourses || self == .topDiscourses
    }
}

enum DiscourseHomeItem: Hashable {
    case discourse(Discourse)
    case track(DiscourseAudio)
    /// A device-library track from the local playback history.
    case localTrack(DiscourseLocalTrack)
}

struct DiscourseHomeSection: Hashable {
    let kind: DiscourseHomeSectionKind
    let items: [DiscourseHomeItem]
}

enum DiscourseHomeContent {
    /// Builds the visible sections in product order, dropping the empty ones.
    /// The recently played tracks section is omitted while playback history is
    /// switched off; the weekly top lists are global and stay visible.
    static func sections(recentDiscourses: [Discourse],
                         recentTracks: [DiscourseAudio],
                         topDiscourses: [Discourse],
                         topTracks: [DiscourseAudio],
                         localTracks: [DiscourseLocalTrack] = [],
                         historyEnabled: Bool) -> [DiscourseHomeSection] {
        var sections: [DiscourseHomeSection] = []

        let recentDiscourseItems = capped(unique(recentDiscourses)).map { DiscourseHomeItem.discourse($0) }
        if !recentDiscourseItems.isEmpty {
            sections.append(DiscourseHomeSection(kind: .recentlyPlayedDiscourses,
                                                 items: recentDiscourseItems))
        }

        if historyEnabled {
            // The discourse history and the device library's history are two
            // independently ordered lists (the store keeps no timestamps), so
            // the discourse entries lead and the library entries follow, deduped
            // by media identity and capped together (AGENTS section 6.1).
            let discourseItems = unique(recentTracks).map { DiscourseHomeItem.track($0) }
            let libraryItems = unique(localTracks).map { DiscourseHomeItem.localTrack($0) }
            let recentTrackItems = Array((discourseItems + libraryItems)
                .prefix(DiscourseHistoryStore.limit))
            if !recentTrackItems.isEmpty {
                sections.append(DiscourseHomeSection(kind: .recentlyPlayedTracks,
                                                     items: recentTrackItems))
            }
        }

        let topDiscourseItems = unique(topDiscourses).map { DiscourseHomeItem.discourse($0) }
        if !topDiscourseItems.isEmpty {
            sections.append(DiscourseHomeSection(kind: .topDiscourses,
                                                 items: topDiscourseItems))
        }

        let topTrackItems = unique(topTracks).map { DiscourseHomeItem.track($0) }
        if !topTrackItems.isEmpty {
            sections.append(DiscourseHomeSection(kind: .topTracks,
                                                 items: topTrackItems))
        }

        return sections
    }

    // MARK: - Internals

    private static func unique(_ items: [Discourse]) -> [Discourse] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }

    private static func unique(_ items: [DiscourseAudio]) -> [DiscourseAudio] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }

    private static func capped(_ items: [Discourse]) -> [Discourse] {
        Array(items.prefix(DiscourseHistoryStore.limit))
    }

    private static func unique(_ items: [DiscourseLocalTrack]) -> [DiscourseLocalTrack] {
        var seen = Set<URL>()
        return items.filter { seen.insert($0.url).inserted }
    }
}
