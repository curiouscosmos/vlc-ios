/*****************************************************************************
 * DiscourseMixerTests.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * Unit coverage for the Audio Mixer's state: documented defaults, membership,
 * selection, ordering, removal, volume clamping and persistence. The follow,
 * fade and audio-session behaviour needs a real player and is a manual check
 * (AGENTS.md section 8).
 *****************************************************************************/

import XCTest
@testable import VLC

final class DiscourseMixerTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "discourse-mixer-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private var settings: DiscourseSettings {
        DiscourseSettings(defaults: defaults)
    }

    private func makeMixer(settings: DiscourseSettings? = nil) -> DiscourseAudioMixer {
        return DiscourseAudioMixer(settings: settings ?? self.settings,
                                   notificationCenter: NotificationCenter())
    }

    private func fileURL(_ name: String) -> URL {
        return FileManager.default.temporaryDirectory
            .appendingPathComponent(name)
            .standardizedFileURL
    }

    // MARK: - Defaults

    func testDefaultsMatchTheContract() {
        let mixer = makeMixer()

        XCTAssertTrue(mixer.items.isEmpty)
        XCTAssertNil(mixer.selectedURL)
        XCTAssertFalse(mixer.isEnabled)
        XCTAssertTrue(mixer.isLooping)
        XCTAssertEqual(mixer.volume, DiscourseAudioMixer.defaultVolume)
        XCTAssertFalse(mixer.isPlaying)
    }

    // MARK: - Membership

    func testAddKeepsOrderAndSelectsTheFirstTrack() {
        let mixer = makeMixer()
        let first = fileURL("first.mp3")
        let second = fileURL("second.mp3")

        XCTAssertTrue(mixer.add(first))
        XCTAssertTrue(mixer.add(second))
        XCTAssertEqual(mixer.items, [first, second])
        XCTAssertEqual(mixer.selectedURL, first)
        XCTAssertEqual(mixer.selectedIndex, 0)
    }

    func testAddingTheSameFileTwiceIsIgnored() {
        let mixer = makeMixer()
        let file = fileURL("track.mp3")

        XCTAssertTrue(mixer.add(file))
        XCTAssertFalse(mixer.add(file))
        XCTAssertEqual(mixer.items.count, 1)
    }

    func testNonFileURLIsRejected() throws {
        let mixer = makeMixer()
        let remote = try XCTUnwrap(URL(string: "https://example.com/track.mp3"))

        XCTAssertFalse(mixer.add(remote))
        XCTAssertTrue(mixer.items.isEmpty)
    }

    func testSelectAndMovePersist() {
        let mixer = makeMixer()
        let a = fileURL("a.mp3")
        let b = fileURL("b.mp3")
        let c = fileURL("c.mp3")
        mixer.add(a)
        mixer.add(b)
        mixer.add(c)

        mixer.select(c)
        mixer.move(from: 2, to: 0)

        XCTAssertEqual(mixer.items, [c, a, b])
        XCTAssertEqual(mixer.selectedURL, c)

        let reopened = makeMixer()
        XCTAssertEqual(reopened.items, [c, a, b])
        XCTAssertEqual(reopened.selectedURL, c)
    }

    func testRemovingTheSelectedTrackSelectsTheNext() {
        let mixer = makeMixer()
        let a = fileURL("a.mp3")
        let b = fileURL("b.mp3")
        mixer.add(a)
        mixer.add(b)

        mixer.remove(at: 0)

        XCTAssertEqual(mixer.items, [b])
        XCTAssertEqual(mixer.selectedURL, b)
    }

    func testClearEmptiesAndPersists() {
        let mixer = makeMixer()
        mixer.add(fileURL("a.mp3"))
        mixer.add(fileURL("b.mp3"))

        mixer.clear()

        XCTAssertTrue(mixer.items.isEmpty)
        XCTAssertNil(mixer.selectedURL)
        XCTAssertTrue(makeMixer().items.isEmpty)
    }

    // MARK: - Switches and volume

    func testSwitchesPersist() {
        let mixer = makeMixer()
        mixer.setEnabled(true)
        mixer.setLooping(false)

        let reopened = makeMixer()
        XCTAssertTrue(reopened.isEnabled)
        XCTAssertFalse(reopened.isLooping)
    }

    func testVolumeIsClampedAndPersisted() {
        let mixer = makeMixer()

        mixer.setVolume(500)
        XCTAssertEqual(mixer.volume, DiscourseAudioMixer.maximumVolume)
        mixer.setVolume(-20)
        XCTAssertEqual(mixer.volume, DiscourseAudioMixer.minimumVolume)
        mixer.setVolume(73)

        XCTAssertEqual(makeMixer().volume, 73)
    }

    func testVolumeNeverChangesWhenOtherSettingsChange() {
        let mixer = makeMixer()
        mixer.setVolume(42)
        mixer.setEnabled(true)
        mixer.select(fileURL("a.mp3"))

        XCTAssertEqual(mixer.volume, 42)
    }

    // MARK: - Copy

    func testDisplayTitleUsesTheFileName() {
        XCTAssertEqual(DiscourseAudioMixer.displayTitle(for: fileURL("Morning Talk.mp3")),
                       "Morning Talk")
        XCTAssertEqual(DiscourseAudioMixer.displayTitle(for: fileURL("Talk%20Two.mp3")),
                       "Talk Two")
    }
}
