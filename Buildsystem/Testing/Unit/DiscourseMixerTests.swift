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
    private var testDirectory: URL!

    override func setUp() {
        super.setUp()
        suiteName = "discourse-mixer-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("discourse-mixer-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        try? FileManager.default.removeItem(at: testDirectory)
        testDirectory = nil
        super.tearDown()
    }

    private var settings: DiscourseSettings {
        DiscourseSettings(defaults: defaults)
    }

    private var fileImporter: DiscourseMixerFileImporter {
        DiscourseMixerFileImporter(directory: testDirectory.appendingPathComponent("Imports",
                                                                                   isDirectory: true))
    }

    private func makeMixer(settings: DiscourseSettings? = nil) -> DiscourseAudioMixer {
        return DiscourseAudioMixer(settings: settings ?? self.settings,
                                   notificationCenter: NotificationCenter(),
                                   fileImporter: fileImporter)
    }

    private func fileURL(_ name: String) -> URL {
        return FileManager.default.temporaryDirectory
            .appendingPathComponent(name)
            .standardizedFileURL
    }

    private func makeSourceFile(_ name: String,
                                in subdirectory: String = "Source",
                                contents: String = "audio") throws -> URL {
        let directory = testDirectory.appendingPathComponent(subdirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
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

    func testPlayButtonDoesNotStartWithoutMainPlayback() {
        let mixer = makeMixer()
        XCTAssertTrue(mixer.add(fileURL("Mixer.mp3")))
        mixer.togglePlayback()
        XCTAssertTrue(mixer.isEnabled)
        XCTAssertFalse(mixer.isPlaying)
    }

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

    func testStaleContainerURLsAreRebasedToTheCurrentContainer() throws {
        // A reinstall moves the app container; the persisted absolute URL still
        // names the old one. The mixer must find the file in the new container.
        let relative = "Documents/mixer-rebase-\(UUID().uuidString).m4a"
        let current = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: current.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: current)
        defer { try? FileManager.default.removeItem(at: current) }

        let stale = URL(fileURLWithPath: "/var/mobile/Containers/Data/Application/"
            + UUID().uuidString + "/" + relative)
        settings.encode([stale.absoluteString], forKey: DiscourseAudioMixer.filesKey)
        settings.set(stale.absoluteString, forKey: DiscourseAudioMixer.selectedKey)

        let mixer = makeMixer()

        XCTAssertEqual(mixer.items, [current])
        XCTAssertEqual(mixer.selectedURL, current)
        XCTAssertEqual(settings.string(DiscourseAudioMixer.selectedKey), current.absoluteString)
        XCTAssertEqual(settings.decode([String].self, forKey: DiscourseAudioMixer.filesKey),
                       [current.absoluteString])
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

    // MARK: - File imports

    func testImportCopiesFileAndPersistsMixerMembership() throws {
        let source = try makeSourceFile("Morning Talk.mp3")
        let imported = try fileImporter.import(source)

        XCTAssertNotEqual(imported, source)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imported.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(DiscourseAudioMixer.displayTitle(for: imported), "Morning Talk")

        let mixer = makeMixer()
        XCTAssertTrue(mixer.add(imported))
        XCTAssertEqual(makeMixer().items, [imported])
    }

    func testImportingTheSameSourceTwiceReusesTheCopy() throws {
        let source = try makeSourceFile("Talk.mp3")
        let first = try fileImporter.import(source)
        let second = try fileImporter.import(source)

        XCTAssertEqual(first, second)
        let mixer = makeMixer()
        XCTAssertTrue(mixer.add(first))
        XCTAssertFalse(mixer.add(second))
        XCTAssertEqual(mixer.items.count, 1)
    }

    func testSameFilenameFromDifferentSourcesKeepsDistinctCopies() throws {
        let first = try makeSourceFile("Talk.mp3", in: "A", contents: "first")
        let second = try makeSourceFile("Talk.mp3", in: "B", contents: "second")

        let firstImport = try fileImporter.import(first)
        let secondImport = try fileImporter.import(second)

        XCTAssertNotEqual(firstImport, secondImport)
        XCTAssertEqual(try Data(contentsOf: firstImport), Data("first".utf8))
        XCTAssertEqual(try Data(contentsOf: secondImport), Data("second".utf8))
        XCTAssertEqual(DiscourseAudioMixer.displayTitle(for: firstImport), "Talk")
        XCTAssertEqual(DiscourseAudioMixer.displayTitle(for: secondImport), "Talk")
    }

    func testImportFailureLeavesNoPartialCopy() throws {
        let missing = testDirectory.appendingPathComponent("Missing.mp3")

        XCTAssertThrowsError(try fileImporter.import(missing))

        let imports = testDirectory.appendingPathComponent("Imports", isDirectory: true)
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: imports.path)) ?? []
        XCTAssertTrue(contents.isEmpty)
    }

    func testImportRejectsAnEmptyFile() throws {
        let source = try makeSourceFile("Empty.mp3", contents: "")

        XCTAssertThrowsError(try fileImporter.import(source))
    }

    func testRemoveDeletesOnlyTheMixerOwnedCopy() throws {
        let source = try makeSourceFile("Imported.mp3")
        let imported = try fileImporter.import(source)
        let external = try makeSourceFile("External.mp3", in: "Elsewhere")
        let mixer = makeMixer()
        mixer.add(imported)
        mixer.add(external)

        mixer.remove(at: 0)

        XCTAssertFalse(FileManager.default.fileExists(atPath: imported.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: external.path))
        XCTAssertEqual(mixer.items, [external])
    }

    func testClearDeletesImportedCopiesButNotOtherFiles() throws {
        let firstSource = try makeSourceFile("One.mp3", in: "A")
        let secondSource = try makeSourceFile("Two.mp3", in: "B")
        let first = try fileImporter.import(firstSource)
        let second = try fileImporter.import(secondSource)
        let external = try makeSourceFile("External.mp3", in: "Elsewhere")
        let mixer = makeMixer()
        mixer.add(first)
        mixer.add(second)
        mixer.add(external)

        mixer.clear()

        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstSource.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondSource.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: external.path))
        XCTAssertTrue(mixer.items.isEmpty)
    }

    // MARK: - Copy

    func testDisplayTitleUsesTheFileName() {
        XCTAssertEqual(DiscourseAudioMixer.displayTitle(for: fileURL("Morning Talk.mp3")),
                       "Morning Talk")
        XCTAssertEqual(DiscourseAudioMixer.displayTitle(for: fileURL("Talk%20Two.mp3")),
                       "Talk Two")
    }
}
