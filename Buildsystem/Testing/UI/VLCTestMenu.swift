/*****************************************************************************
 * VLCTestMenu.swift
 * VLC for iOSUITests
 *****************************************************************************
 * Copyright (c) 2018 VideoLAN. All rights reserved.
 * $Id$
 *
 * Authors: Mike JS. Choi <mkchoi212 # icloud.com>
 *
 * Refer to the COPYING file of the official project for license.
 *****************************************************************************/

import Foundation
import XCTest

/// The five Rajneesh Discourse destinations, in product order. Replaces the
/// upstream tab assertions (Video / Audio / Playlist / Browse / Settings).
class VLCTestMenu: XCTestCase {
    let app = XCUIApplication()
    var helper: TestHelper!

    override func setUp() {
        super.setUp()

        XCUIDevice.shared.orientation = .portrait
        helper = TestHelper(app)
        app.launch()
    }

    func testNavigationToHome() {
        helper.tapTabBarItem(VLCAccessibilityIdentifier.home)
        XCTAssertTrue(app.navigationBars[VLCAccessibilityIdentifier.home].waitForExistence(timeout: 5))
    }

    func testNavigationToDiscourses() {
        helper.tapTabBarItem(VLCAccessibilityIdentifier.discourses)
        XCTAssertTrue(app.navigationBars[VLCAccessibilityIdentifier.discourses].waitForExistence(timeout: 5))
    }

    func testNavigationToSearch() {
        helper.tapTabBarItem(VLCAccessibilityIdentifier.search)
        XCTAssertTrue(app.navigationBars[VLCAccessibilityIdentifier.search].waitForExistence(timeout: 5))
    }

    func testNavigationToPlaylists() {
        helper.tapTabBarItem(VLCAccessibilityIdentifier.playlist)
        XCTAssertTrue(app.navigationBars[VLCAccessibilityIdentifier.playlist].waitForExistence(timeout: 5))
    }

    func testAutomaticFavouriteCollectionsAndUnavailableNavigation() {
        app.terminate()
        app.launchArguments = [
            "-osho_api_liked_discourses", "(favouritetestdiscourse)",
            "-osho_api_liked_audios", "(favouritetesttrack)",
            "-osho_api_likes_fetched_at", String(Date().timeIntervalSince1970)
        ]
        app.launch()
        helper.tapTabBarItem(VLCAccessibilityIdentifier.playlist)
        let tracks = app.buttons["favourite-tracks"]
        let discourses = app.buttons["favourite-discourses"]
        XCTAssertTrue(tracks.waitForExistence(timeout: 5))
        XCTAssertTrue(discourses.exists)
        tracks.tap()
        XCTAssertTrue(app.navigationBars.staticTexts["Favourite Tracks"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Unavailable track")).firstMatch.exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        discourses.tap()
        XCTAssertTrue(app.navigationBars.staticTexts["Favourite Discourses"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Unavailable discourse")).firstMatch.exists)
        app.terminate()
        app.launchArguments = []
        app.launch()
        helper.tapTabBarItem(VLCAccessibilityIdentifier.playlist)
        XCTAssertTrue(app.buttons["favourite-tracks"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["favourite-discourses"].exists)
    }

    func testNavigationToAudioMixer() {
        helper.tapTabBarItem(VLCAccessibilityIdentifier.audioMixer)
        XCTAssertTrue(app.navigationBars[VLCAccessibilityIdentifier.audioMixer].waitForExistence(timeout: 5))
    }

    func testAudioMixerShowsThePanelAndOpensTheAudioPicker() {
        helper.tapTabBarItem(VLCAccessibilityIdentifier.audioMixer)
        XCTAssertTrue(app.navigationBars[VLCAccessibilityIdentifier.audioMixer].waitForExistence(timeout: 5))

        XCTAssertTrue(app.buttons["discourseMixerEnabled"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Loop track"].exists)
        XCTAssertTrue(app.sliders["Mixer volume"].exists)
        XCTAssertTrue(app.buttons["More options"].exists)
        let heading = app.buttons["Background Music Mixer"]
        heading.tap()
        XCTAssertFalse(app.sliders["Mixer volume"].exists)
        heading.tap()
        XCTAssertTrue(app.sliders["Mixer volume"].exists)

        // Tracks persist between runs; clear them so the empty state is
        // deterministic (and so the test leaves no mixer state behind).
        let clear = app.buttons["Clear all"].firstMatch
        if clear.waitForExistence(timeout: 2) {
            clear.tap()
            XCTAssertTrue(app.buttons["Remove all"].waitForExistence(timeout: 3))
            app.buttons["Remove all"].tap()
        }

        // The removed Local Library screen must not be offered anywhere here.
        XCTAssertFalse(app.buttons["Open local library"].exists)
        let addAudio = app.buttons["Add audio file"].firstMatch
        XCTAssertTrue(addAudio.waitForExistence(timeout: 5))
        addAudio.tap()

        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        cancel.tap()
        XCTAssertTrue(app.buttons["discourseMixerEnabled"].waitForExistence(timeout: 5))
    }

    func testDiscoursesShowsCatalogueWithoutSegments() {
        helper.tapTabBarItem(VLCAccessibilityIdentifier.discourses)
        XCTAssertTrue(app.buttons["Filter"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Local"].exists)
        XCTAssertFalse(app.buttons["Discourse"].exists)
    }

    func testCatalogueFilterMenu() {
        helper.tapTabBarItem(VLCAccessibilityIdentifier.discourses)

        let filter = app.buttons["Filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        filter.tap()

        XCTAssertTrue(app.buttons["All languages"].waitForExistence(timeout: 5))
        app.buttons["Sort"].tap()
        XCTAssertTrue(app.buttons["Most liked"].waitForExistence(timeout: 5))
        app.buttons["Most liked"].tap()

        // Applying the sort reloads the catalogue; clearing it restores the
        // default order so the next test starts from a clean filter state.
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        filter.tap()
        let clear = app.buttons["Clear filters"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        clear.tap()
    }

    func testCatalogueOpensDiscourseDetail() {
        helper.tapTabBarItem(VLCAccessibilityIdentifier.discourses)

        let card = app.collectionViews.cells.firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        card.tap()

        XCTAssertTrue(app.buttons["discoursePlayAll"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.tables["discourseTracks"].exists)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["Filter"].waitForExistence(timeout: 5))
    }

    func testDiscourseLikeTogglesFromTheDetailHeader() {
        helper.tapTabBarItem(VLCAccessibilityIdentifier.discourses)

        let card = app.collectionViews.cells.firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        card.tap()

        let likeButton = app.buttons["discourseDetailLike"]
        XCTAssertTrue(likeButton.waitForExistence(timeout: 15))

        // The likes of this install persist between runs; start from unliked so
        // the assertions below are deterministic, and unlike again at the end so
        // the test leaves no like behind on the server.
        if likeButton.label.hasPrefix("Unlike") {
            toggleLike(likeButton, expecting: "Like ")
        }

        toggleLike(likeButton, expecting: "Unlike")
        toggleLike(likeButton, expecting: "Like ")
    }

    /// Taps the heart and waits for the optimistic label *and* for the request
    /// to settle: the store ignores a second tap while one is in flight.
    private func toggleLike(_ button: XCUIElement, expecting prefix: String) {
        button.tap()
        wait(for: button, prefix: prefix)
        let settled = NSPredicate(format: "value != %@", "Updating")
        let expectation = XCTNSPredicateExpectation(predicate: settled, object: button)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 15), .completed,
                       "the like request did not settle")
    }

    func testTrackDownloadAndRemoval() throws {
        helper.tapTabBarItem(VLCAccessibilityIdentifier.discourses)

        let card = app.collectionViews.cells.firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        card.tap()

        let download = app.buttons["discourseTrackDownload"].firstMatch
        XCTAssertTrue(download.waitForExistence(timeout: 15))

        // A whole discourse track is ~40 MB; allow the CDN time to deliver it.
        download.tap()
        let downloaded = NSPredicate(format: "label BEGINSWITH %@", "Downloaded")
        let downloadExpectation = XCTNSPredicateExpectation(predicate: downloaded, object: download)
        guard XCTWaiter().wait(for: [downloadExpectation], timeout: 150) == .completed else {
            // The CDN can be slow; leave nothing running and report a skip
            // instead of failing the whole suite on a network hiccup.
            let menu = app.buttons["discourseDownloadsMenu"]
            if menu.exists {
                menu.tap()
                let cancelAll = app.buttons["Cancel downloads"]
                if cancelAll.waitForExistence(timeout: 3) {
                    cancelAll.tap()
                }
            }
            throw XCTSkip("the track did not finish downloading within the budget")
        }

        // Remove it again through the discourse menu so the test leaves nothing
        // behind on the simulator (a downloaded track is hundreds of megabytes
        // across runs).
        let menu = app.buttons["discourseDownloadsMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        let removeAll = app.buttons["Remove all downloads"]
        XCTAssertTrue(removeAll.waitForExistence(timeout: 5))
        removeAll.tap()

        let confirm = app.buttons["Remove all"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        let missing = NSPredicate(format: "label BEGINSWITH %@", "Download ")
        let settled = XCTNSPredicateExpectation(predicate: missing, object: download)
        XCTAssertEqual(XCTWaiter().wait(for: [settled], timeout: 30), .completed,
                       "the download was not removed")
    }

    private func wait(for element: XCUIElement, prefix: String) {
        let predicate = NSPredicate(format: "label BEGINSWITH %@", prefix)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 15), .completed,
                       "expected the like control to read \(prefix)… but it read \(element.label)")
    }

    func testSearchFindsDiscoursesAndTracks() {
        helper.tapTabBarItem(VLCAccessibilityIdentifier.search)

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        // The trailing newline presses the keyboard's search key, which runs
        // the query immediately instead of waiting for the debounce.
        field.typeText("dhyan\n")

        let results = app.tables["discourseSearchResults"]
        XCTAssertTrue(results.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Discourses"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.staticTexts["Tracks"].exists, true)
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 20))

        // Tapping a discourse result opens its detail screen.
        let discourse = app.cells["discourseSearchDiscourse"].firstMatch
        XCTAssertTrue(discourse.waitForExistence(timeout: 20))
        discourse.tap()
        XCTAssertTrue(app.buttons["discoursePlayAll"].waitForExistence(timeout: 20))
    }

    func testSearchTrackStartsPlayback() {
        helper.tapTabBarItem(VLCAccessibilityIdentifier.search)

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("dhyan\n")

        let results = app.tables["discourseSearchResults"]
        XCTAssertTrue(results.waitForExistence(timeout: 20))

        let track = app.cells["discourseSearchTrack"].firstMatch
        XCTAssertTrue(track.waitForExistence(timeout: 20))
        track.tap()

        // Starting a track presents the upstream full-screen audio player.
        XCTAssertTrue(app.buttons[VLCAccessibilityIdentifier.moreOptions].waitForExistence(timeout: 30))
    }

    func testHomeShowsRecentlyPlayedDiscourse() {
        helper.tapTabBarItem(VLCAccessibilityIdentifier.discourses)

        let card = app.collectionViews.cells.firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        let cardLabel = card.label
        card.tap()
        XCTAssertTrue(app.buttons["discoursePlayAll"].waitForExistence(timeout: 15))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        helper.tapTabBarItem(VLCAccessibilityIdentifier.home)

        let home = app.collectionViews["discourseHome"]
        XCTAssertTrue(home.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Recently played"].waitForExistence(timeout: 10))

        // A previous visit may have left the grid scrolled under the navigation
        // bar, where the card is not tappable; start from the top.
        home.swipeDown()

        // The discourse just opened is the newest entry, so it is the first
        // recently played card. Match it by the label the catalogue card shows.
        let homeCard = home.cells.matching(NSPredicate(format: "label == %@", cardLabel)).firstMatch
        XCTAssertTrue(homeCard.waitForExistence(timeout: 10))
        homeCard.tap()
        XCTAssertTrue(app.buttons["discoursePlayAll"].waitForExistence(timeout: 15))
    }

    func testPlaybackHistorySettingToggles() {
        helper.tapTabBarItem(VLCAccessibilityIdentifier.home)
        XCTAssertTrue(app.buttons[VLCAccessibilityIdentifier.settings].waitForExistence(timeout: 5))
        app.buttons[VLCAccessibilityIdentifier.settings].tap()
        let openSettings = app.buttons[VLCAccessibilityIdentifier.openSettings]
        XCTAssertTrue(openSettings.waitForExistence(timeout: 5))
        openSettings.tap()

        let history = app.switches["Playback history"]
        XCTAssertTrue(history.waitForExistence(timeout: 10))
        let initial = (history.value as? String) == "1"

        history.tap()
        let flipped = NSPredicate(format: "value == %@", initial ? "0" : "1")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: flipped, object: history)],
                                        timeout: 5), .completed)

        history.tap()
        let restored = NSPredicate(format: "value == %@", initial ? "1" : "0")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: restored, object: history)],
                                        timeout: 5), .completed)

        let close = app.buttons[VLCAccessibilityIdentifier.done]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
    }

    func testNavigationToAbout() {
        helper.tapTabBarItem(VLCAccessibilityIdentifier.home)
        app.navigationBars[VLCAccessibilityIdentifier.home].buttons[VLCAccessibilityIdentifier.settings].tap()
        app.buttons[VLCAccessibilityIdentifier.about].tap()
        XCTAssertTrue(app.navigationBars.buttons[VLCAccessibilityIdentifier.done].waitForExistence(timeout: 5))
    }
}
