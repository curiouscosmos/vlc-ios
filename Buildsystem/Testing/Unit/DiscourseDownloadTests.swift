/*****************************************************************************
 * DiscourseDownloadTests.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * Unit coverage for the download store: records, verified local files, per-
 * discourse counts and removal, pruning of records whose file vanished and
 * deletion of files no record mentions. The background transfer itself is a
 * manual device check (AGENTS.md section 8).
 *****************************************************************************/

import XCTest
@testable import VLC

final class DiscourseDownloadTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var directory: URL!

    override func setUp() {
        super.setUp()
        suiteName = "discourse-downloads-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("discourse-downloads-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        super.tearDown()
    }

    private var settings: DiscourseSettings {
        DiscourseSettings(defaults: defaults)
    }

    private func makeStore() -> DiscourseDownloadStore {
        return DiscourseDownloadStore(settings: settings, directoryURL: directory)
    }

    /// Writes a small file outside the downloads directory and hands it to the
    /// store, the way a finished URLSession download arrives.
    @discardableResult
    private func finishDownload(_ store: DiscourseDownloadStore,
                                audioID: String,
                                discourseID: String = "d1",
                                bytes: Int = 16) throws -> URL {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("source-\(UUID().uuidString)")
        try Data(repeating: 0x41, count: bytes).write(to: source)
        try store.storeDownloadedFile(at: source,
                                      audioID: audioID,
                                      discourseID: discourseID)
        return source
    }

    // MARK: - Records

    func testStoredFileIsFoundAndCounted() throws {
        let store = makeStore()
        try finishDownload(store, audioID: "a1")

        let url = try XCTUnwrap(store.localURL(for: "a1"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(url.pathExtension, "audio")
        XCTAssertTrue(store.isDownloaded(audioID: "a1"))
        XCTAssertEqual(store.discourseID(for: "a1"), "d1")
        XCTAssertEqual(store.downloadedCount(forDiscourse: "d1"), 1)
        XCTAssertEqual(store.downloadedAudioIDs(forDiscourse: "d1"), ["a1"])
        XCTAssertEqual(store.downloadedCount(forDiscourse: "d2"), 0)
    }

    func testRecordsSurviveAFreshStoreInstance() throws {
        try finishDownload(makeStore(), audioID: "a1")
        let reopened = makeStore()

        XCTAssertTrue(reopened.isDownloaded(audioID: "a1"))
        XCTAssertEqual(reopened.downloadedCount(forDiscourse: "d1"), 1)
    }

    func testEmptyFileIsNotConsideredDownloaded() throws {
        let store = makeStore()
        try finishDownload(store, audioID: "a1", bytes: 0)

        XCTAssertNil(store.localURL(for: "a1"))
        XCTAssertFalse(store.isDownloaded(audioID: "a1"))
    }

    func testCorruptRecordsAreTreatedAsEmpty() throws {
        defaults.set(Data("not json".utf8),
                     forKey: DiscourseDownloadStore.downloadsKey)
        defaults.set(Data("{}".utf8),
                     forKey: DiscourseDownloadStore.discoursesKey)

        let store = makeStore()
        XCTAssertNil(store.filename(for: "a1"))
        XCTAssertEqual(store.downloadedCount(forDiscourse: "d1"), 0)
    }

    func testUnsafeIdentifiersStayInsideTheDownloadsDirectory() throws {
        let store = makeStore()
        try finishDownload(store, audioID: "../../a1/b2")

        let url = try XCTUnwrap(store.localURL(for: "../../a1/b2"))
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL.path,
                       directory.standardizedFileURL.path)
    }

    // MARK: - Removal

    func testRemoveDeletesFileAndRecords() throws {
        let store = makeStore()
        try finishDownload(store, audioID: "a1")
        let url = try XCTUnwrap(store.localURL(for: "a1"))

        XCTAssertTrue(store.remove(audioID: "a1"))

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNil(store.localURL(for: "a1"))
        XCTAssertNil(store.filename(for: "a1"))
        XCTAssertEqual(store.downloadedCount(forDiscourse: "d1"), 0)
        XCTAssertFalse(store.remove(audioID: "a1"))
    }

    func testRemoveAllOnlyTouchesOneDiscourse() throws {
        let store = makeStore()
        try finishDownload(store, audioID: "a1", discourseID: "d1")
        try finishDownload(store, audioID: "a2", discourseID: "d1")
        try finishDownload(store, audioID: "a3", discourseID: "d2")
        let removed = try XCTUnwrap(store.localURL(for: "a2"))

        XCTAssertEqual(store.removeAll(forDiscourse: "d1"), 2)

        XCTAssertFalse(FileManager.default.fileExists(atPath: removed.path))
        XCTAssertFalse(store.isDownloaded(audioID: "a1"))
        XCTAssertTrue(store.isDownloaded(audioID: "a3"))
        XCTAssertEqual(store.downloadedCount(forDiscourse: "d2"), 1)
    }

    func testRemoveAllDeletesEverything() throws {
        let store = makeStore()
        try finishDownload(store, audioID: "a1", discourseID: "d1")
        try finishDownload(store, audioID: "a2", discourseID: "d2")

        XCTAssertEqual(store.removeAll(), 2)
        XCTAssertFalse(store.isDownloaded(audioID: "a1"))
        XCTAssertFalse(store.isDownloaded(audioID: "a2"))
        XCTAssertEqual(store.downloadedCount(forDiscourse: "d1"), 0)
    }

    // MARK: - Housekeeping

    func testRecordWhoseFileVanishedIsPrunedOnLaunch() throws {
        let store = makeStore()
        try finishDownload(store, audioID: "a1")
        let url = try XCTUnwrap(store.localURL(for: "a1"))
        try FileManager.default.removeItem(at: url)

        let reopened = makeStore()
        XCTAssertNil(reopened.filename(for: "a1"))
        XCTAssertEqual(reopened.downloadedCount(forDiscourse: "d1"), 0)
    }

    func testOrphanFileIsDeletedOnLaunch() throws {
        let store = makeStore()
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        let orphan = directory.appendingPathComponent("orphan.audio")
        try Data(repeating: 0x42, count: 8).write(to: orphan)

        _ = makeStore()

        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertFalse(store.isDownloaded(audioID: "orphan"))
    }
}
