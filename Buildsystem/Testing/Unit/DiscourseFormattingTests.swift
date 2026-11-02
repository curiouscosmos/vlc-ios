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
 * the track rows and the like controls (999 / 1.2k / 12k / 1m), and for the
 * track row's trailing controls keeping their width when a title is long.
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

    func testPlayerHeartUsesLargeSizeOnlyWithoutLikes() throws {
        let control = DiscourseLikeControl()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let controller = UIViewController()
        window.rootViewController = controller
        controller.view.addSubview(control)
        control.frame = CGRect(x: 0, y: 0, width: 80, height: 44)
        window.isHidden = false
        defer { window.isHidden = true }
        let stack = try XCTUnwrap(control.subviews.compactMap { $0 as? UIStackView }.first)
        let heart = try XCTUnwrap(stack.arrangedSubviews.compactMap { $0 as? UIImageView }.first)
        control.style = .player
        for (count, expectedSize) in [(0, 24.0), (2, 18.0), (0, 24.0)] {
            control.configure(isLiked: false, count: count, title: "Track", isPending: false)
            window.layoutIfNeeded()
            XCTAssertEqual(heart.bounds.width, expectedSize, accuracy: 0.01)
        }
        control.style = .surface
        window.layoutIfNeeded()
        XCTAssertEqual(heart.bounds.width, 18, accuracy: 0.01)
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

    func testTrackRowKeepsTrailingControlsAtTheirIntrinsicWidth() throws {
        // 430 pt reproduces the Pro Max tie the screenshots show; 320 pt is the
        // narrowest supported phone. Positive like counts widen the group too.
        for width in [CGFloat(320), 430] {
            for likeCount in [0, 12_345] {
                try assertTrailingControlsFit(at: width, likeCount: likeCount)
            }
        }
    }

    private func assertTrailingControlsFit(at width: CGFloat, likeCount: Int) throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 480))
        let controller = UIViewController()
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }

        let cell = DiscourseTrackCell(style: .default,
                                      reuseIdentifier: DiscourseTrackCell.reuseIdentifier)
        controller.view.addSubview(cell)

        let track = DiscourseAudio(id: "a1",
                                   discourseID: "d1",
                                   discourseName: "Ancient Music In The Pines",
                                   title: "Ancient Music In The Pines 01",
                                   audioURLString: "https://example.com/a.mp3",
                                   durationSeconds: 5263)
        cell.configure(with: track,
                       position: 1,
                       fraction: 0,
                       isCompleted: false,
                       isPlaying: false,
                       like: DiscourseLikeState(isLiked: false, count: likeCount, isPending: false),
                       download: .missing)

        // A generous height keeps the row's horizontal arbitration under test.
        cell.frame = CGRect(x: 0, y: 0, width: width, height: 200)
        window.layoutIfNeeded()
        cell.layoutIfNeeded()

        let labels = allLabels(in: cell)
        let title = try XCTUnwrap(labels.first { $0.text == track.title })
        let duration = try XCTUnwrap(labels.first { $0.text == "1:27:43" })
        let download = try XCTUnwrap(firstSubview(ofType: DiscourseDownloadControl.self, in: cell))
        let like = try XCTUnwrap(firstSubview(ofType: DiscourseLikeControl.self, in: cell))

        let trailing = [duration, download, like].map { $0.convert($0.bounds, to: cell.contentView) }
        // The duration, download and like controls must never be squeezed into
        // each other; a long title gives way and wraps instead.
        XCTAssertGreaterThanOrEqual(trailing[0].width + 0.5, duration.intrinsicContentSize.width)
        XCTAssertGreaterThanOrEqual(trailing[1].width + 0.5, download.intrinsicContentSize.width)
        XCTAssertGreaterThanOrEqual(trailing[2].width + 0.5, like.intrinsicContentSize.width)
        XCTAssertLessThanOrEqual(trailing[0].maxX, trailing[1].minX + 0.5)
        XCTAssertLessThanOrEqual(trailing[1].maxX, trailing[2].minX + 0.5)

        let titleFrame = title.convert(title.bounds, to: cell.contentView)
        XCTAssertLessThanOrEqual(titleFrame.maxX, trailing[0].minX - 9)
        let textHeight = (track.title as NSString).boundingRect(
            with: CGSize(width: titleFrame.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: title.font],
            context: nil).height
        XCTAssertGreaterThan(textHeight, title.font.lineHeight * 1.5,
                             "a long title should use its second line")
    }

    // MARK: - Helpers

    private func allLabels(in root: UIView) -> [UILabel] {
        var result = (root as? UILabel).map { [$0] } ?? []
        for subview in root.subviews {
            result.append(contentsOf: allLabels(in: subview))
        }
        return result
    }

    private func firstSubview<T: UIView>(ofType type: T.Type, in root: UIView) -> T? {
        if let match = root as? T {
            return match
        }
        for subview in root.subviews {
            if let match = firstSubview(ofType: type, in: subview) {
                return match
            }
        }
        return nil
    }
}
