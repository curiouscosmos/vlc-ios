/*****************************************************************************
 * DiscourseFormattingTests.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * Unit coverage for the compact count formatting used by the catalogue cards,
 * the track rows and the like controls (999 / 1.2k / 12k / 1m).
 *****************************************************************************/

import XCTest
import UIKit
@testable import VLC

final class DiscourseFormattingTests: XCTestCase {
    func testTrackSubtitleOmitsDuplicateTitleAndKeepsDurationFirst() {
        XCTAssertEqual(DiscourseMetadataText.trackSubtitle(title: "Talk 001", discourseName: " talk 001 ",
                                                          durationSeconds: 5940), "1:39:00")
        XCTAssertEqual(DiscourseMetadataText.trackSubtitle(title: "Talk 001", discourseName: "Series",
                                                          durationSeconds: 5940), "1:39:00 · Series")
        XCTAssertEqual(DiscourseMetadataText.trackSubtitle(title: "Talk", discourseName: "Talk",
                                                          durationSeconds: nil), "")
    }

    func testCatalogueIndexLetters() {
        XCTAssertEqual(DiscourseCatalogueViewController.indexLetter(for: " A Bird on the Wing"), "A")
        XCTAssertEqual(DiscourseCatalogueViewController.indexLetter(for: "écho"), "E")
        XCTAssertEqual(DiscourseCatalogueViewController.indexLetter(for: "beyond"), "B")
        XCTAssertEqual(DiscourseCatalogueViewController.indexLetter(for: "123"), "#")
        XCTAssertEqual(DiscourseCatalogueViewController.indexLetter(for: ""), "#")
        XCTAssertEqual(DiscourseCatalogueViewController.indexLetter(for: "ध्यान"), "#")
    }

    func testCountsBelowOneThousandAreVerbatim() {
        XCTAssertEqual(DiscourseCountFormatter.string(for: 0), "0")
        XCTAssertEqual(DiscourseCountFormatter.string(for: 1), "1")
        XCTAssertEqual(DiscourseCountFormatter.string(for: 42), "42")
        XCTAssertEqual(DiscourseCountFormatter.string(for: 999), "999")
    }

    func testThousandsUseOneDecimalBelowTen() {
        XCTAssertEqual(DiscourseCountFormatter.string(for: 1_000), "1k")
        XCTAssertEqual(DiscourseCountFormatter.string(for: 1_200), "1.2k")
        XCTAssertEqual(DiscourseCountFormatter.string(for: 1_250), "1.3k")
        XCTAssertEqual(DiscourseCountFormatter.string(for: 1_500), "1.5k")
        XCTAssertEqual(DiscourseCountFormatter.string(for: 9_900), "9.9k")
    }

    func testThousandsUseWholeNumbersFromTen() {
        XCTAssertEqual(DiscourseCountFormatter.string(for: 9_950), "10k")
        XCTAssertEqual(DiscourseCountFormatter.string(for: 12_345), "12k")
        XCTAssertEqual(DiscourseCountFormatter.string(for: 999_499), "999k")
    }

    func testTheRoundedThousandBecomesOneMillion() {
        XCTAssertEqual(DiscourseCountFormatter.string(for: 999_500), "1m")
    }

    func testMillions() {
        XCTAssertEqual(DiscourseCountFormatter.string(for: 1_000_000), "1m")
        XCTAssertEqual(DiscourseCountFormatter.string(for: 1_200_000), "1.2m")
        XCTAssertEqual(DiscourseCountFormatter.string(for: 2_000_000), "2m")
        XCTAssertEqual(DiscourseCountFormatter.string(for: 10_000_000), "10m")
    }

    func testNegativeCountsReadAsZero() {
        XCTAssertEqual(DiscourseCountFormatter.string(for: -5), "0")
    }

    func testLikeCountsAppearOnlyWhenPositive() {
        let control = DiscourseLikeControl()
        let stack = control.subviews.compactMap { $0 as? UIStackView }.first!
        let countLabel = stack.arrangedSubviews.compactMap { $0 as? UILabel }.first!

        control.configure(isLiked: false, count: 0, title: "", isPending: false)
        XCTAssertTrue(countLabel.isHidden)
        control.configure(isLiked: true, count: 1, title: "", isPending: false)
        XCTAssertFalse(countLabel.isHidden)
        XCTAssertEqual(countLabel.text, "1")
        control.configure(isLiked: false, count: 0, title: "", isPending: false)
        XCTAssertTrue(countLabel.isHidden)

        let noLikes = DiscourseMetadataText.summary(language: "", tracks: 2, likes: 0)
        XCTAssertEqual(noLikes, DiscourseMetadataText.tracks(2))
        XCTAssertEqual(DiscourseMetadataText.summary(language: "", tracks: 2, likes: 1),
                       noLikes + " · " + DiscourseMetadataText.likes(1))
    }
}
