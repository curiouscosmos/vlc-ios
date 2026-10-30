/*****************************************************************************
 * DiscourseDeepLinkTests.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * Pins the website deep-link shape shared with the Android reference:
 * /discourses/{id} and /discourses/{id}/tracks/{audioId}.
 *****************************************************************************/

import XCTest
@testable import VLC

final class DiscourseDeepLinkTests: XCTestCase {
    func testDiscoursePageIsParsed() {
        let link = DiscourseDeepLink(url: URL(string: "https://rajneeshdiscourse.com/discourses/discourse-id")!)
        XCTAssertEqual(link?.discourseID, "discourse-id")
        XCTAssertNil(link?.audioID)
    }

    func testTrackPageIsParsedWithAudioID() {
        let link = DiscourseDeepLink(url: URL(string: "https://rajneeshdiscourse.com/discourses/discourse-id/tracks/audio-id?x=1")!)
        XCTAssertEqual(link?.discourseID, "discourse-id")
        XCTAssertEqual(link?.audioID, "audio-id")
    }

    func testTrailingSlashAndWwwHostAreAccepted() {
        let link = DiscourseDeepLink(url: URL(string: "https://www.rajneeshdiscourse.com/discourses/discourse-id/")!)
        XCTAssertEqual(link?.discourseID, "discourse-id")
        XCTAssertNil(link?.audioID)
    }

    func testHttpAndCaseInsensitivePathAreAccepted() {
        let link = DiscourseDeepLink(url: URL(string: "http://RajneeshDiscourse.com/Discourses/discourse-id/Tracks/audio-id")!)
        XCTAssertEqual(link?.discourseID, "discourse-id")
        XCTAssertEqual(link?.audioID, "audio-id")
    }

    func testTrackURLBuilderMatchesTheWebsiteShape() throws {
        let url = try XCTUnwrap(DiscourseDeepLink.trackURL(discourseID: "discourse-id",
                                                          audioID: "audio-id"))
        XCTAssertEqual(url.absoluteString,
                       "https://rajneeshdiscourse.com/discourses/discourse-id/tracks/audio-id")
        let parsed = DiscourseDeepLink(url: url)
        XCTAssertEqual(parsed?.discourseID, "discourse-id")
        XCTAssertEqual(parsed?.audioID, "audio-id")
    }

    func testClipURLIncludesDiscourseTrackAndSelectedSeconds() throws {
        let discourseID = "1a98eec7-c66d-5f9b-a31f-449dfb541eaa"
        let audioID = "575089a6-42f7-5288-97cc-d5c2a7fdadb2"
        let url = try XCTUnwrap(DiscourseDeepLink.clipURL(discourseID: discourseID, audioID: audioID, start: 60, end: 90))
        XCTAssertEqual(url.absoluteString,
                       "https://rajneeshdiscourse.com/discourses/\(discourseID)/tracks/\(audioID)?start=60&end=90")
        let parsed = try XCTUnwrap(DiscourseDeepLink(url: url))
        XCTAssertEqual(parsed.discourseID, discourseID)
        XCTAssertEqual(parsed.audioID, audioID)
    }

    func testClipURLPreservesFractionalSecondsAndRejectsInvalidRanges() throws {
        let url = try XCTUnwrap(DiscourseDeepLink.clipURL(discourseID: "d", audioID: "a", start: 0.25, end: 2.75))
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                       [URLQueryItem(name: "start", value: "0.25"), URLQueryItem(name: "end", value: "2.75")])
        for (start, end) in [(-1.0, 2.0), (2, 2), (2, 1), (.nan, 2), (0, .infinity)] {
            XCTAssertNil(DiscourseDeepLink.clipURL(discourseID: "d", audioID: "a", start: start, end: end))
        }
        XCTAssertNil(DiscourseDeepLink.clipURL(discourseID: "", audioID: "a", start: 0, end: 2))
    }

    func testUnrelatedURLsAreRejected() {
        XCTAssertNil(DiscourseDeepLink(url: URL(string: "https://rajneeshdiscourse.com/")!))
        XCTAssertNil(DiscourseDeepLink(url: URL(string: "https://rajneeshdiscourse.com/discourses")!))
        XCTAssertNil(DiscourseDeepLink(url: URL(string: "https://rajneeshdiscourse.com/discourses/id/other/audio")!))
        XCTAssertNil(DiscourseDeepLink(url: URL(string: "https://rajneeshdiscourse.com/discourses/id/tracks")!))
        XCTAssertNil(DiscourseDeepLink(url: URL(string: "https://example.com/discourses/id")!))
        XCTAssertNil(DiscourseDeepLink(url: URL(string: "mailto:test@example.com")!))
    }

    func testEmptyIdentifiersAreRejected() {
        XCTAssertNil(DiscourseDeepLink(url: URL(string: "https://rajneeshdiscourse.com/discourses/%20")!))
        XCTAssertNil(DiscourseDeepLink(url: URL(string: "https://rajneeshdiscourse.com/discourses/id/tracks/%20")!))
    }
}
