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
    func testVersionCheckUsesOnlyIOSMinimumAndNumericComponents() throws {
        let data = Data(#"{"ios":{"minSupportedVersion":"1.2.0","unstableVersions":["2.0.0"],"forceUpdate":true},"android":{"minSupportedVersion":"99.0","forceUpdate":true}}"#.utf8)
        let policy = try JSONDecoder().decode(DiscourseVersionCheck.self, from: data).ios
        XCTAssertTrue(policy.forceUpdate)
        for version in ["0.9", "1.1.99", "1.0.10"] {
            XCTAssertTrue(policy.requiresUpdate(currentVersion: version), version)
        }
        for version in ["1.2", "1.2.0", "1.2.0.0", "1.2.1", "1.10.0", "2.0.0"] {
            XCTAssertFalse(policy.requiresUpdate(currentVersion: version), version)
        }
        for version in ["", "1..0", "-1.0", "1.x", "1.0-beta", "18446744073709551616"] {
            XCTAssertFalse(policy.requiresUpdate(currentVersion: version), version)
            XCTAssertFalse(DiscourseVersionPolicy(minSupportedVersion: version, forceUpdate: true)
                .requiresUpdate(currentVersion: "1.0"), version)
        }
        XCTAssertTrue(DiscourseVersionPolicy(minSupportedVersion: "1.0.0.1", forceUpdate: false)
            .requiresUpdate(currentVersion: "1"))
        XCTAssertEqual(DiscourseVersionCheck.request?.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(DiscourseVersionCheck.request?.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
        XCTAssertNil(DiscourseVersionCheck.request?.value(forHTTPHeaderField: "x-api-key"))
    }

    @MainActor
    func testUpdateDialogAllowsSkippingOnlyOptionalUpdates() {
        for forced in [false, true] {
            var skipped = false
            let dialog = DiscourseUpdateViewController(forceUpdate: forced, update: {}, skip: { skipped = true })
            dialog.loadViewIfNeeded()
            dialog.view.frame = CGRect(x: 0, y: 0, width: 320, height: 568)
            dialog.view.setNeedsLayout()
            dialog.view.layoutIfNeeded()
            let card = dialog.view.subviews.compactMap { $0 as? UIScrollView }.first
            XCTAssertGreaterThan(card?.contentSize.height ?? 0, 100)
            XCTAssertTrue(dialog.view.bounds.contains(card?.frame ?? .zero))
            func buttons(in view: UIView) -> [UIButton] {
                (view as? UIButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
            }
            XCTAssertEqual(buttons(in: dialog.view).count, forced ? 1 : 2)
            XCTAssertTrue(dialog.accessibilityPerformEscape())
            XCTAssertEqual(skipped, !forced)
        }
    }

    func testDiscourseOptionalMetadataDecodesAndSurvivesCacheRoundTrip() throws {
        let decoder = JSONDecoder()
        for payload in [#"{"id":"d","date":null,"location":null}"#,
                        #"{"id":"d"}"#,
                        #"{"id":"d","date":"1974-06-10","location":"Pune, Maharashtra, India"}"#] {
            let discourse = try decoder.decode(Discourse.self, from: Data(payload.utf8))
            let restored = try decoder.decode(Discourse.self, from: JSONEncoder().encode(discourse))
            XCTAssertEqual(restored, discourse)
            if discourse.date != nil {
                XCTAssertEqual(discourse.date, "1974-06-10")
                XCTAssertEqual(discourse.location, "Pune, Maharashtra, India")
            } else { XCTAssertNil(discourse.location) }
        }
    }

    func testDiscourseDateAndLocationFormatting() {
        let locale = Locale(identifier: "en_US")
        XCTAssertEqual(DiscourseMetadataText.date("1974-06-10", locale: locale), "Jun 10, 1974")
        XCTAssertEqual(DiscourseMetadataText.date("1974-06-10T23:00:00-07:00", locale: locale), "Jun 10, 1974")
        XCTAssertEqual(DiscourseMetadataText.date("1974-06-10 00:00:00", locale: locale), "Jun 10, 1974")
        for value in [nil, "", " ", "not a date", "1974-02-31"] as [String?] {
            XCTAssertNil(DiscourseMetadataText.date(value, locale: locale))
        }
        XCTAssertEqual(DiscourseMetadataText.location(" Pune, Maharashtra, India "), "Pune")
        XCTAssertEqual(DiscourseMetadataText.location("Mumbai"), "Mumbai")
        for value in [nil, "", "  ", ", India"] as [String?] { XCTAssertNil(DiscourseMetadataText.location(value)) }
    }

    @MainActor
    func testDiscourseCardsMatchAcrossHostsAndHideMissingMetadata() throws {
        let discourse = Discourse(id: "d", title: "A Bird on the Wing", language: "english",
                                  date: "1974-06-10", location: "Pune, Maharashtra, India", totalTracks: 11)
        let like = DiscourseLikeState(isLiked: false, count: 2, isPending: false)
        let summary = DiscourseDownloadSummary(downloaded: 0, active: 0, total: 11)
        let card = DiscourseCardCell()
        card.configure(with: discourse, like: like, downloads: summary)
        for width in [CGFloat(288), 358, 800] {
            let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: 0, section: 0))
            attributes.size = CGSize(width: width, height: 160)
            let fitted = card.preferredLayoutAttributesFitting(attributes)
            XCTAssertEqual(fitted.size.width, width, "Self-sizing must retain the host's full card width")
            XCTAssertGreaterThanOrEqual(fitted.size.height, 132)
        }
        let search = DiscourseSearchCell(style: .default, reuseIdentifier: nil)
        search.configure(with: discourse, like: like)
        let cardView = try XCTUnwrap(firstSubview(ofType: DiscourseCardView.self, in: card))
        let searchView = try XCTUnwrap(firstSubview(ofType: DiscourseCardView.self, in: search))
        XCTAssertEqual(cardView.accessibilityLabel, searchView.accessibilityLabel)
        XCTAssertTrue(cardView.accessibilityLabel?.contains("Pune") == true)
        XCTAssertFalse(cardView.accessibilityLabel?.contains("Maharashtra") == true)
        var opens = 0, likes = 0
        card.onOpen = { opens += 1 }; card.onToggleLike = { likes += 1 }
        let button = try XCTUnwrap(firstSubview(ofType: DiscourseAccessibilityButton.self, in: card))
        XCTAssertTrue(button.accessibilityActivate())
        let heart = try XCTUnwrap(firstSubview(ofType: DiscourseLikeControl.self, in: card))
        heart.sendActions(for: .touchUpInside)
        XCTAssertEqual(opens, 1); XCTAssertEqual(likes, 1)
        card.prepareForReuse()
        card.configure(with: Discourse(id: "empty", title: "No metadata"), like: like, downloads: summary)
        let visibleLabels = allLabels(in: card).filter { label in
            var current: UIView? = label
            while let view = current { if view.isHidden { return false }; current = view.superview }
            return true
        }.compactMap { $0.text }
        XCTAssertFalse(visibleLabels.contains("Pune"))
        XCTAssertFalse(visibleLabels.contains("Jun 10, 1974"))
        XCTAssertFalse(visibleLabels.contains("English"))
    }

    @MainActor
    func testDiscourseCardLayoutsInBothThemesAndAccessibilitySizes() throws {
        let original = PresentationTheme.current
        defer { PresentationTheme.current = original }
        for (name, theme) in [("dark", PresentationTheme.darkTheme), ("light", .brightTheme)] {
            PresentationTheme.current = theme
            for width in [CGFloat(288), 358, 800] {
                for accessible in [false, true] {
                    let card = DiscourseCardView()
                    let controller = UIViewController()
                    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
                    let window = UIWindow(windowScene: scene)
                    window.rootViewController = controller
                    window.makeKeyAndVisible()
                    defer { window.isHidden = true }
                    controller.view.addSubview(card)
                    if #available(iOS 17.0, *) {
                        controller.traitOverrides.preferredContentSizeCategory = accessible ? .accessibilityExtraExtraExtraLarge : .large
                    }
                    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                    card.configure(with: Discourse(id: "d", title: "A Bird on the Wing", language: "english",
                        date: "1974-06-10", location: "Pune, Maharashtra, India", totalTracks: 11),
                        like: DiscourseLikeState(isLiked: false, count: 2, isPending: false),
                        downloads: DiscourseDownloadSummary(downloaded: 0, active: 0, total: 11))
                    card.frame = CGRect(x: 0, y: 0, width: width, height: 200)
                    card.layoutIfNeeded()
                    let size = card.systemLayoutSizeFitting(CGSize(width: width, height: 0),
                        withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
                    card.frame.size = size
                    card.layoutIfNeeded()
                    XCTAssertGreaterThanOrEqual(size.height, 132)
                    for label in allLabels(in: card) where label.text?.isEmpty == false {
                        var current: UIView? = label
                        var hidden = false
                        while let view = current { hidden = hidden || view.isHidden; current = view.superview }
                        if hidden { continue }
                        let rect = label.convert(label.bounds, to: card)
                        XCTAssertGreaterThan(rect.width, 0)
                        XCTAssertGreaterThanOrEqual(rect.height + 0.5, label.font.lineHeight)
                        XCTAssertGreaterThanOrEqual(rect.minX, -0.5)
                        XCTAssertLessThanOrEqual(rect.maxX, width + 0.5)
                        XCTAssertLessThanOrEqual(rect.maxY, size.height + 0.5)
                    }
                    let image = UIGraphicsImageRenderer(bounds: card.bounds).image { context in card.layer.render(in: context.cgContext) }
                    let name = "discourse-card-\(name)-\(Int(width))-\(accessible ? "accessible" : "regular")"
                    try image.pngData()?.write(to: FileManager.default.temporaryDirectory.appendingPathComponent(name + ".png"))
                    let attachment = XCTAttachment(image: image)
                    attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
                }
            }
        }
    }

    @MainActor
    func testDetailHeaderMetadataChipsAndLayouts() throws {
        let original = PresentationTheme.current
        defer { PresentationTheme.current = original }
        let like = DiscourseLikeState(isLiked: false, count: 2, isPending: false)
        for (themeName, theme) in [("dark", PresentationTheme.darkTheme), ("light", .brightTheme)] {
            PresentationTheme.current = theme
            for width in [CGFloat(320), 800] {
                for accessible in [false, true] {
                    let header = DiscourseDetailHeaderView()
                    let controller = UIViewController()
                    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
                    let window = UIWindow(windowScene: scene)
                    window.rootViewController = controller
                    window.makeKeyAndVisible()
                    defer { window.isHidden = true }
                    controller.view.addSubview(header)
                    if #available(iOS 17.0, *) {
                        controller.traitOverrides.preferredContentSizeCategory = accessible ? .accessibilityExtraExtraExtraLarge : .large
                    }
                    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                    let discourse = Discourse(id: "d", title: "A Bird on the Wing", language: "english",
                        date: "1974-06-10 09:00:00", location: "Pune, Maharashtra, India", totalTracks: 11)
                    header.configure(with: discourse, like: like)
                    header.frame = CGRect(x: 0, y: 0, width: width, height: 500)
                    header.layoutIfNeeded()
                    header.frame.size = header.systemLayoutSizeFitting(CGSize(width: width, height: 0),
                        withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
                    header.layoutIfNeeded()
                    let chips = header.subviews.flatMap { descendants(in: $0) }.compactMap { $0 as? DiscourseCardMetadata }
                    let city = try XCTUnwrap(chips.first { $0.accessibilityIdentifier == "discourseDetailLocation" })
                    let date = try XCTUnwrap(chips.first { $0.accessibilityIdentifier == "discourseDetailDate" })
                    XCTAssertEqual(city.text, "Pune")
                    XCTAssertEqual(date.text, DiscourseMetadataText.date(discourse.date))
                    let title = try XCTUnwrap(allLabels(in: header).first { $0.text == discourse.title })
                    let titleFrame = title.convert(title.bounds, to: header)
                    let summary = try XCTUnwrap(allLabels(in: header).first {
                        $0.text == DiscourseMetadataText.summary(language: discourse.language,
                                                               tracks: discourse.totalTracks, likes: 0)
                    })
                    let summaryFrame = summary.convert(summary.bounds, to: header)
                    let heartFrame = header.likeControl.convert(header.likeControl.bounds, to: header)
                    let playFrame = header.playAllButton.convert(header.playAllButton.bounds, to: header)
                    XCTAssertGreaterThanOrEqual(summaryFrame.minY, titleFrame.maxY)
                    XCTAssertGreaterThanOrEqual(heartFrame.minY, summaryFrame.maxY)
                    XCTAssertGreaterThanOrEqual(playFrame.minY, heartFrame.maxY)
                    if !accessible {
                        XCTAssertEqual(city.convert(city.bounds, to: header).midY, playFrame.midY, accuracy: 0.5)
                        XCTAssertEqual(date.convert(date.bounds, to: header).midY, playFrame.midY, accuracy: 0.5)
                    }
                    for chip in [city, date] {
                        XCTAssertFalse(chip.isHidden)
                        XCTAssertEqual(chip.accessibilityLabel, chip.text)
                        let frame = chip.convert(chip.bounds, to: header)
                        XCTAssertGreaterThanOrEqual(frame.minY, titleFrame.maxY)
                        XCTAssertLessThanOrEqual(frame.maxX, width + 0.5)
                        XCTAssertLessThanOrEqual(frame.maxY, header.bounds.height + 0.5)
                    }
                    let image = UIGraphicsImageRenderer(bounds: header.bounds).image { context in
                        DiscourseColors.current.appBackground.setFill()
                        context.fill(header.bounds)
                        header.layer.render(in: context.cgContext)
                    }
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "Discourse header \(themeName) \(Int(width)) \(accessible ? "accessible" : "regular")"
                    attachment.lifetime = .keepAlways; add(attachment)
                    for (rawDate, rawLocation) in [(nil, nil), (discourse.date, nil), (nil, discourse.location), ("invalid", " , India")] as [(String?, String?)] {
                        header.configure(with: Discourse(id: "d", title: discourse.title, date: rawDate, location: rawLocation), like: like)
                        XCTAssertEqual(city.isHidden, DiscourseMetadataText.location(rawLocation) == nil)
                        XCTAssertEqual(date.isHidden, DiscourseMetadataText.date(rawDate) == nil)
                        if city.isHidden && date.isHidden { XCTAssertTrue(city.superview?.isHidden == true) }
                    }
                }
            }
        }
    }

    private func descendants(in view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { descendants(in: $0) }
    }

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
