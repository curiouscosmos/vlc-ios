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
