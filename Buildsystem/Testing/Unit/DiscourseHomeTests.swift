/*****************************************************************************
 * DiscourseHomeTests.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * Unit coverage for the Home section assembly: product order, empty sections
 * dropped, recently played tracks hidden while playback history is off, ids
 * deduped and the recently-played lists capped at 24.
 *****************************************************************************/

import XCTest
@testable import VLC

final class DiscourseHomeTests: XCTestCase {
    func testEmptyPayloadsProduceNoSections() {
        let sections = DiscourseHomeContent.sections(recentDiscourses: [],
                                                     recentTracks: [],
                                                     topDiscourses: [],
                                                     topTracks: [],
                                                     historyEnabled: true)
        XCTAssertTrue(sections.isEmpty)
    }

    func testTopListsShowLoadingPlaceholdersWhileStatsLoad() {
        let sections = DiscourseHomeContent.sections(recentDiscourses: [discourse("recent-d")],
                                                     recentTracks: [],
                                                     topDiscourses: [],
                                                     topTracks: [],
                                                     historyEnabled: true,
                                                     topListsLoading: true)

        XCTAssertEqual(sections.map(\.kind), [.recentlyPlayedDiscourses,
                                              .topDiscourses,
                                              .topTracks])
        XCTAssertEqual(sections[1].items, [.loading])
        XCTAssertEqual(sections[2].items, [.loading])
    }

    func testSectionsFollowProductOrder() {
        let sections = DiscourseHomeContent.sections(
            recentDiscourses: [discourse("recent-d")],
            recentTracks: [track("recent-a")],
            topDiscourses: [discourse("top-d")],
            topTracks: [track("top-a")],
            historyEnabled: true)

        XCTAssertEqual(sections.map(\.kind), [.recentlyPlayedDiscourses,
                                              .recentlyPlayedTracks,
                                              .topDiscourses,
                                              .topTracks])
        XCTAssertEqual(sections[0].items, [.discourse(discourse("recent-d"))])
        XCTAssertEqual(sections[1].items, [.track(track("recent-a"))])
        XCTAssertEqual(sections[2].items, [.discourse(discourse("top-d"))])
        XCTAssertEqual(sections[3].items, [.track(track("top-a"))])
    }

    func testEmptySectionsAreDropped() {
        let sections = DiscourseHomeContent.sections(recentDiscourses: [],
                                                     recentTracks: [],
                                                     topDiscourses: [discourse("top-d")],
                                                     topTracks: [],
                                                     historyEnabled: true)

        XCTAssertEqual(sections.map(\.kind), [.topDiscourses])
    }

    func testRecentTracksAreHiddenWhileHistoryIsOff() {
        let sections = DiscourseHomeContent.sections(recentDiscourses: [discourse("recent-d")],
                                                     recentTracks: [track("recent-a")],
                                                     topDiscourses: [],
                                                     topTracks: [track("top-a")],
                                                     historyEnabled: false)

        XCTAssertEqual(sections.map(\.kind), [.recentlyPlayedDiscourses, .topTracks],
                       "the weekly top tracks are global and stay visible")
    }

    func testIdsAreDedupedKeepingTheNewestEntry() {
        let sections = DiscourseHomeContent.sections(
            recentDiscourses: [discourse("d1"), discourse("d2"), discourse("d1")],
            recentTracks: [track("a1"), track("a1")],
            topDiscourses: [discourse("d3"), discourse("d3")],
            topTracks: [],
            historyEnabled: true)

        XCTAssertEqual(sections[0].items, [.discourse(discourse("d1")), .discourse(discourse("d2"))])
        XCTAssertEqual(sections[1].items, [.track(track("a1"))])
        XCTAssertEqual(sections[2].items, [.discourse(discourse("d3"))])
    }

    func testRecentlyPlayedListsCapAtTwentyFour() {
        let manyDiscourses = (0..<30).map { discourse("d\($0)") }
        let manyTracks = (0..<30).map { track("a\($0)") }

        let sections = DiscourseHomeContent.sections(recentDiscourses: manyDiscourses,
                                                     recentTracks: manyTracks,
                                                     topDiscourses: [],
                                                     topTracks: [],
                                                     historyEnabled: true)

        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].items.count, DiscourseHistoryStore.limit)
        XCTAssertEqual(sections[1].items.count, DiscourseHistoryStore.limit)
        XCTAssertEqual(sections[0].items.first, .discourse(discourse("d0")))
    }

    // MARK: - Device library history

    func testLocalHistoryFollowsTheDiscourseHistory() {
        let local = localTrack("file1")
        let sections = DiscourseHomeContent.sections(recentDiscourses: [],
                                                     recentTracks: [track("a1")],
                                                     topDiscourses: [],
                                                     topTracks: [],
                                                     localTracks: [local],
                                                     historyEnabled: true)

        XCTAssertEqual(sections.map(\.kind), [.recentlyPlayedTracks])
        XCTAssertEqual(sections[0].items, [.track(track("a1")), .localTrack(local)])
    }

    func testLocalHistoryIsHiddenWhileHistoryIsOff() {
        let sections = DiscourseHomeContent.sections(recentDiscourses: [],
                                                     recentTracks: [],
                                                     topDiscourses: [],
                                                     topTracks: [],
                                                     localTracks: [localTrack("file1")],
                                                     historyEnabled: false)

        XCTAssertTrue(sections.isEmpty)
    }

    func testLocalHistoryDedupesByMediaIdentity() {
        let sections = DiscourseHomeContent.sections(recentDiscourses: [],
                                                     recentTracks: [],
                                                     topDiscourses: [],
                                                     topTracks: [],
                                                     localTracks: [localTrack("a"),
                                                                   localTrack("b"),
                                                                   localTrack("a")],
                                                     historyEnabled: true)

        XCTAssertEqual(sections[0].items, [.localTrack(localTrack("a")),
                                           .localTrack(localTrack("b"))])
    }

    func testMergedRecentTracksCapAtTwentyFour() {
        let discourseTracks = (0..<20).map { track("a\($0)") }
        let localTracks = (0..<20).map { localTrack("f\($0)") }

        let sections = DiscourseHomeContent.sections(recentDiscourses: [],
                                                     recentTracks: discourseTracks,
                                                     topDiscourses: [],
                                                     topTracks: [],
                                                     localTracks: localTracks,
                                                     historyEnabled: true)

        XCTAssertEqual(sections[0].items.count, DiscourseHistoryStore.limit)
        let expected = discourseTracks.map { DiscourseHomeItem.track($0) }
        XCTAssertEqual(Array(sections[0].items.prefix(20)), expected)
        XCTAssertEqual(sections[0].items.last, .localTrack(localTrack("f3")))
    }

    // MARK: - Fixtures

    private func discourse(_ id: String) -> Discourse {
        Discourse(id: id, title: "Discourse \(id)")
    }

    private func localTrack(_ name: String) -> DiscourseLocalTrack {
        return DiscourseLocalTrack(url: URL(fileURLWithPath: "/tmp/\(name).mp3"),
                                   title: name,
                                   subtitle: nil,
                                   artworkURL: nil,
                                   durationSeconds: 60,
                                   media: nil)
    }

    private func track(_ id: String) -> DiscourseAudio {
        DiscourseAudio(id: id,
                       discourseID: "d1",
                       discourseName: "Discourse",
                       title: "Track \(id)",
                       audioURLString: "https://osho.b-cdn.net/OSHO/\(id).mp3")
    }
}
