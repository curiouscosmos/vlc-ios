/*****************************************************************************
 * DiscourseSearchTests.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * Unit coverage for the search result accumulator: appending both endpoints,
 * deduping ids across pages, and following the deeper of the two page counts.
 *****************************************************************************/

import XCTest
@testable import VLC

final class DiscourseSearchTests: XCTestCase {
    func testAppendKeepsBothSectionsAndTracksPaging() {
        var results = DiscourseSearchResults()
        results.append(discourses: page([discourse("d1"), discourse("d2")], page: 1, totalPages: 3),
                       tracks: pageOfTracks([track("a1")], page: 1, totalPages: 5))

        XCTAssertEqual(results.discourses.map(\.id), ["d1", "d2"])
        XCTAssertEqual(results.tracks.map(\.id), ["a1"])
        XCTAssertEqual(results.page, 1)
        XCTAssertEqual(results.totalPages, 5)
        XCTAssertTrue(results.hasMore)
        XCTAssertFalse(results.isEmpty)
    }

    func testAppendDedupesIdsAcrossPages() {
        var results = DiscourseSearchResults()
        results.append(discourses: page([discourse("d1"), discourse("d2")], page: 1, totalPages: 2),
                       tracks: pageOfTracks([track("a1"), track("a2")], page: 1, totalPages: 2))
        results.append(discourses: page([discourse("d2"), discourse("d3")], page: 2, totalPages: 2),
                       tracks: pageOfTracks([track("a2"), track("a3")], page: 2, totalPages: 2))

        XCTAssertEqual(results.discourses.map(\.id), ["d1", "d2", "d3"])
        XCTAssertEqual(results.tracks.map(\.id), ["a1", "a2", "a3"])
        XCTAssertEqual(results.page, 2)
        XCTAssertFalse(results.hasMore)
    }

    func testAppendStopsPagingWhenTheShorterEndpointRunsOut() {
        var results = DiscourseSearchResults()
        results.append(discourses: page([discourse("d1")], page: 1, totalPages: 1),
                       tracks: pageOfTracks([], page: 1, totalPages: 1))

        XCTAssertFalse(results.hasMore)
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.tracks.isEmpty)
    }

    func testEmptyResultsReportNoContent() {
        var results = DiscourseSearchResults()
        results.append(discourses: page([], page: 1, totalPages: 1),
                       tracks: pageOfTracks([], page: 1, totalPages: 1))

        XCTAssertTrue(results.isEmpty)
        XCTAssertFalse(results.hasMore)
    }

    func testResetClearsEverything() {
        var results = DiscourseSearchResults()
        results.append(discourses: page([discourse("d1")], page: 1, totalPages: 4),
                       tracks: pageOfTracks([track("a1")], page: 1, totalPages: 4))
        results.reset()

        XCTAssertTrue(results.discourses.isEmpty)
        XCTAssertTrue(results.tracks.isEmpty)
        XCTAssertEqual(results.page, 0)
        XCTAssertEqual(results.totalPages, 0)
        XCTAssertFalse(results.hasMore)
    }

    // MARK: - Fixtures

    private func page(_ discourses: [Discourse], page: Int, totalPages: Int) -> DiscoursePage<Discourse> {
        DiscoursePage(data: discourses,
                      meta: DiscoursePaginationMeta(page: page, totalPages: totalPages))
    }

    private func pageOfTracks(_ tracks: [DiscourseAudio], page: Int, totalPages: Int) -> DiscoursePage<DiscourseAudio> {
        DiscoursePage(data: tracks,
                      meta: DiscoursePaginationMeta(page: page, totalPages: totalPages))
    }

    private func discourse(_ id: String) -> Discourse {
        Discourse(id: id, title: "Discourse \(id)")
    }

    private func track(_ id: String) -> DiscourseAudio {
        DiscourseAudio(id: id,
                       discourseID: "d1",
                       discourseName: "Discourse",
                       title: "Track \(id)",
                       audioURLString: "https://osho.b-cdn.net/OSHO/\(id).mp3")
    }
}
