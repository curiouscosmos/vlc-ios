/*****************************************************************************
 * DiscoursePlaybackTests.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * Unit coverage for the playback layer: track durations, the durable URL to
 * identity index used to attribute a restored queue to the right discourse, and
 * the identity carried by catalogue payloads.
 *****************************************************************************/

import XCTest
@testable import VLC

final class DiscoursePlaybackTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "discourse-playback-\(UUID().uuidString)"
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

    func testArtworkSwipeThresholds() {
        XCTAssertEqual(AudioPlayerViewController.artworkSwipeDirection(translation: -75, velocity: 0, width: 300), -1)
        XCTAssertEqual(AudioPlayerViewController.artworkSwipeDirection(translation: 75, velocity: 0, width: 300), 1)
        XCTAssertEqual(AudioPlayerViewController.artworkSwipeDirection(translation: 20, velocity: 501, width: 300), 1)
        XCTAssertEqual(AudioPlayerViewController.artworkSwipeDirection(translation: -20, velocity: -501, width: 300), -1)
        XCTAssertEqual(AudioPlayerViewController.artworkSwipeDirection(translation: 20, velocity: -600, width: 300), 0)
        XCTAssertEqual(AudioPlayerViewController.artworkSwipeDirection(translation: 20, velocity: 500, width: 300), 0)
        XCTAssertEqual(AudioPlayerViewController.artworkSwipeDirection(translation: 74, velocity: 0, width: 300), 0)
        XCTAssertEqual(AudioPlayerViewController.artworkSwipeDirection(translation: 0, velocity: 600, width: 0), 0)
    }

    // MARK: - Durations

    func testDurationFormatting() {
        XCTAssertEqual(DiscourseDurationFormatter.string(forSeconds: 0), "0:00")
        XCTAssertEqual(DiscourseDurationFormatter.string(forSeconds: 42), "0:42")
        XCTAssertEqual(DiscourseDurationFormatter.string(forSeconds: 59.4), "0:59")
        XCTAssertEqual(DiscourseDurationFormatter.string(forSeconds: 60), "1:00")
        XCTAssertEqual(DiscourseDurationFormatter.string(forSeconds: 3_599), "59:59")
        XCTAssertEqual(DiscourseDurationFormatter.string(forSeconds: 3_600), "1:00:00")
        XCTAssertEqual(DiscourseDurationFormatter.string(forSeconds: 3_661), "1:01:01")
    }

    func testDurationFormattingRejectsUnknownValues() {
        XCTAssertNil(DiscourseDurationFormatter.string(forSeconds: nil))
        XCTAssertNil(DiscourseDurationFormatter.string(forSeconds: -1))
        XCTAssertNil(DiscourseDurationFormatter.string(forSeconds: .nan))
        XCTAssertNil(DiscourseDurationFormatter.string(forSeconds: .infinity))
    }

    // MARK: - Identity store

    func testIdentityStoreRoundTrip() {
        let store = DiscourseMediaIdentityStore(settings: settings)
        let url = URL(string: "https://osho.b-cdn.net/OSHO/discourses/1/1.mp3")!

        XCTAssertNil(store.identity(for: url))

        store.record(url: url,
                     identity: DiscourseMediaIdentity(discourseID: "d1", audioID: "a1"))
        XCTAssertEqual(store.identity(for: url)?.discourseID, "d1")
        XCTAssertEqual(store.identity(for: url)?.audioID, "a1")

        store.reset()
        XCTAssertNil(store.identity(for: url))
    }

    func testIdentityStoreReplacesOlderEntries() {
        let store = DiscourseMediaIdentityStore(settings: settings)
        let url = URL(string: "https://osho.b-cdn.net/OSHO/discourses/1/1.mp3")!

        store.record(url: url,
                     identity: DiscourseMediaIdentity(discourseID: "d1", audioID: "a1"))
        store.record(url: url,
                     identity: DiscourseMediaIdentity(discourseID: "d2", audioID: "a2"))

        XCTAssertEqual(store.identity(for: url)?.audioID, "a2")
    }

    func testIdentityStoreDropsTheOldestEntriesPastTheLimit() {
        var now = Date(timeIntervalSince1970: 1_000)
        let store = DiscourseMediaIdentityStore(settings: settings,
                                                now: { now },
                                                limit: 2)

        for index in 1...3 {
            let url = URL(string: "https://osho.b-cdn.net/OSHO/discourses/1/\(index).mp3")!
            store.record(url: url, identity: DiscourseMediaIdentity(discourseID: "d1", audioID: "a\(index)"))
            now = now.addingTimeInterval(60)
        }

        let oldest = URL(string: "https://osho.b-cdn.net/OSHO/discourses/1/1.mp3")!
        let newest = URL(string: "https://osho.b-cdn.net/OSHO/discourses/1/3.mp3")!
        XCTAssertNil(store.identity(for: oldest))
        XCTAssertEqual(store.identity(for: newest)?.audioID, "a3")
    }

    func testIdentityStoreSurvivesANewInstance() {
        let url = URL(string: "https://osho.b-cdn.net/OSHO/discourses/7/9.mp3")!
        DiscourseMediaIdentityStore(settings: settings)
            .record(url: url, identity: DiscourseMediaIdentity(discourseID: "d7", audioID: "a9"))

        let restored = DiscourseMediaIdentityStore(settings: settings)
        XCTAssertEqual(restored.identity(for: url)?.audioID, "a9")
    }

    func testIdentityStoreIgnoresCorruptStorage() {
        defaults.set(Data("not json".utf8), forKey: DiscourseMediaIdentityStore.settingsKey)
        let store = DiscourseMediaIdentityStore(settings: settings)
        let url = URL(string: "https://osho.b-cdn.net/OSHO/discourses/1/1.mp3")!

        XCTAssertNil(store.identity(for: url))
        store.record(url: url, identity: DiscourseMediaIdentity(discourseID: "d1", audioID: "a1"))
        XCTAssertEqual(store.identity(for: url)?.audioID, "a1")
    }

    // MARK: - Identity from payloads

    func testIdentityFallsBackToTheTrackPayload() throws {
        let track = try decodeTrack()
        let discourse = try decodeDiscourse()

        let identity = DiscourseMediaFactory.identity(for: track, discourse: discourse)
        XCTAssertEqual(identity.discourseID, "discourse-1")
        XCTAssertEqual(identity.audioID, "audio-1")

        let withoutDiscourse = DiscourseMediaFactory.identity(for: track, discourse: nil)
        XCTAssertEqual(withoutDiscourse.discourseID, "discourse-1")
        XCTAssertEqual(withoutDiscourse.audioID, "audio-1")
    }

    // MARK: - Queue

    func testQueueSkipsUnplayableTracksAndAlignsTheStartIndex() throws {
        let store = DiscourseMediaIdentityStore(settings: settings)
        let discourse = try decodeDiscourse()
        let tracks = [try decodeTrack(id: "a1", url: "https://osho.b-cdn.net/OSHO/1.mp3"),
                      try decodeTrack(id: "a2", url: ""),
                      try decodeTrack(id: "a3", url: "https://osho.b-cdn.net/OSHO/3.mp3")]

        let queue = try XCTUnwrap(DiscourseMediaFactory.mediaList(for: tracks,
                                                                  discourse: discourse,
                                                                  startingAt: 1,
                                                                  identityStore: store))
        XCTAssertEqual(queue.mediaList.count, 2)
        XCTAssertEqual(queue.tracks.map(\.id), ["a1", "a3"])
        // The requested track has no URL, so playback falls back to the first
        // playable one instead of pointing past the end.
        XCTAssertEqual(queue.firstIndex, 0)

        let fromThird = try XCTUnwrap(DiscourseMediaFactory.mediaList(for: tracks,
                                                                      discourse: discourse,
                                                                      startingAt: 2,
                                                                      identityStore: store))
        XCTAssertEqual(fromThird.firstIndex, 1)
    }

    func testQueueIsNilWhenNoTrackIsPlayable() throws {
        let store = DiscourseMediaIdentityStore(settings: settings)
        let tracks = [try decodeTrack(id: "a1", url: "")]

        XCTAssertNil(DiscourseMediaFactory.mediaList(for: tracks,
                                                     discourse: try decodeDiscourse(),
                                                     startingAt: 0,
                                                     identityStore: store))
    }

    // MARK: - Media mapping

    func testMediaCarriesTheBriefMetadata() throws {
        let store = DiscourseMediaIdentityStore(settings: settings)
        let media = try XCTUnwrap(DiscourseMediaFactory.media(for: try decodeTrack(),
                                                              discourse: try decodeDiscourse(),
                                                              fallbackTrackNumber: 1,
                                                              identityStore: store))

        XCTAssertEqual(media.metaData.title, "The First Question")
        XCTAssertEqual(media.metaData.artist, "Osho")
        XCTAssertEqual(media.metaData.album, "The Book of Secrets")
        XCTAssertEqual(media.metaData.trackNumber, 1)
        XCTAssertEqual(media.metaData.artworkURL?.absoluteString,
                       "https://osho.b-cdn.net/OSHO/thumbnails/1.jpg")
        XCTAssertEqual(media.length.intValue, 1_234_500)
    }

    func testMediaIdentityIsReadableFromThePlayerItem() throws {
        let store = DiscourseMediaIdentityStore(settings: settings)
        let media = try XCTUnwrap(DiscourseMediaFactory.media(for: try decodeTrack(),
                                                              discourse: try decodeDiscourse(),
                                                              fallbackTrackNumber: 1,
                                                              identityStore: store))

        let identity = try XCTUnwrap(DiscourseMediaFactory.identity(of: media, identityStore: store))
        XCTAssertEqual(identity.discourseID, "discourse-1")
        XCTAssertEqual(identity.audioID, "audio-1")
    }

    func testMediaPrefersAVerifiedDownload() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("discourse-playback-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let downloads = DiscourseDownloadStore(settings: settings, directoryURL: directory)
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("source-\(UUID().uuidString)")
        try Data(repeating: 0x41, count: 32).write(to: source)
        try downloads.storeDownloadedFile(at: source,
                                          audioID: "audio-1",
                                          discourseID: "discourse-1")

        let media = try XCTUnwrap(DiscourseMediaFactory.media(for: try decodeTrack(),
                                                              discourse: try decodeDiscourse(),
                                                              fallbackTrackNumber: 1,
                                                              identityStore: DiscourseMediaIdentityStore(settings: settings),
                                                              downloads: downloads))
        XCTAssertEqual(media.url?.isFileURL, true)
        XCTAssertEqual(media.url?.lastPathComponent, "audio-1.audio")
    }

    func testMediaStreamsWhenTheDownloadedFileIsGone() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("discourse-playback-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let downloads = DiscourseDownloadStore(settings: settings, directoryURL: directory)
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("source-\(UUID().uuidString)")
        try Data(repeating: 0x41, count: 32).write(to: source)
        try downloads.storeDownloadedFile(at: source,
                                          audioID: "audio-1",
                                          discourseID: "discourse-1")
        try FileManager.default.removeItem(at: try XCTUnwrap(downloads.localURL(for: "audio-1")))

        let media = try XCTUnwrap(DiscourseMediaFactory.media(for: try decodeTrack(),
                                                              discourse: try decodeDiscourse(),
                                                              fallbackTrackNumber: 1,
                                                              identityStore: DiscourseMediaIdentityStore(settings: settings),
                                                              downloads: downloads))
        XCTAssertEqual(media.url?.absoluteString,
                       "https://osho.b-cdn.net/OSHO/discourses/1/1.mp3")
    }

    func testIdentityFallsBackToTheURLIndexForARestoredQueue() throws {
        let store = DiscourseMediaIdentityStore(settings: settings)
        _ = DiscourseMediaFactory.media(for: try decodeTrack(),
                                        discourse: try decodeDiscourse(),
                                        fallbackTrackNumber: 1,
                                        identityStore: store)

        // A queue restored from the last-played playlist has no meta extras.
        let restored = try XCTUnwrap(VLCMedia(url: URL(string: "https://osho.b-cdn.net/OSHO/discourses/1/1.mp3")!))
        XCTAssertEqual(DiscourseMediaFactory.identity(of: restored, identityStore: store)?.audioID, "audio-1")
    }

    // MARK: - Fixtures

    private func decodeTrack(id: String = "audio-1",
                             url: String = "https://osho.b-cdn.net/OSHO/discourses/1/1.mp3") throws -> DiscourseAudio {
        let json = """
        {
            "id": "\(id)",
            "discourse_id": "discourse-1",
            "discourse_name": "The Book of Secrets",
            "discourse_thumbnail_url": "/thumbnails/1.jpg",
            "language": "english",
            "title": "The First Question",
            "audio_url": "\(url)",
            "duration_seconds": 1234.5,
            "file_size": 123456,
            "mime_type": "audio/mpeg",
            "track_number": 1,
            "total_likes": 3,
            "created_at": "2026-01-01T00:00:00.000Z",
            "updated_at": "2026-01-01T00:00:00.000Z"
        }
        """
        return try JSONDecoder().decode(DiscourseAudio.self, from: Data(json.utf8))
    }

    private func decodeDiscourse() throws -> Discourse {
        let json = """
        {
            "id": "discourse-1",
            "title": "The Book of Secrets",
            "thumbnail_url": "/thumbnails/1.jpg",
            "language": "english",
            "slug": "the-book-of-secrets",
            "total_tracks": 12,
            "total_likes": 40,
            "created_at": "2026-01-01T00:00:00.000Z",
            "updated_at": "2026-01-01T00:00:00.000Z"
        }
        """
        return try JSONDecoder().decode(Discourse.self, from: Data(json.utf8))
    }
}
