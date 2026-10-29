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
        _ = VLCAppDelegate() // Unit-test hosts do not run the app delegate defaults registration.
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

    private func snapshot(shuffled: Bool = false) -> [String: Any] {
        let items: [[String: Any]] = (0..<3).map {
            ["url": "https://example.com/track\($0).mp3", "title": "Track \($0)",
             "artist": "Osho", "album": "Talks", "duration": 120_000,
             "audioID": "audio-\($0)", "discourseID": "discourse"]
        }
        return ["version": 1, "items": items, "index": 1, "position": 45_000.0,
                "duration": 120_000.0, "shuffle": shuffled, "order": shuffled ? [2, 0, 1] : [], "repeat": 0]
    }

    func testSnapshotRoundTripAndValidation() throws {
        let encoded = try JSONSerialization.data(withJSONObject: snapshot(shuffled: true))
        let valid = try XCTUnwrap(RDPlaybackSnapshot.validated(JSONSerialization.jsonObject(with: encoded)))
        XCTAssertEqual(valid["index"] as? Int, 1)
        XCTAssertEqual(valid["order"] as? [Int], [2, 0, 1])
        XCTAssertEqual(valid["position"] as? Double, 45_000)
        for (key, value) in [("version", 2), ("index", 3), ("index", -1), ("repeat", 3)] {
            var invalid = snapshot()
            invalid[key] = value
            XCTAssertNil(RDPlaybackSnapshot.validated(invalid), key)
        }
        var invalid = snapshot(shuffled: true)
        invalid["order"] = [0, 0, 2]
        XCTAssertNil(RDPlaybackSnapshot.validated(invalid))
        invalid = snapshot()
        invalid["items"] = [["url": "javascript:alert(1)"]]
        XCTAssertNil(RDPlaybackSnapshot.validated(invalid))
        XCTAssertNil(RDPlaybackSnapshot.validated(Data("broken".utf8)))
        invalid = snapshot()
        invalid["position"] = Double.nan
        XCTAssertNil(RDPlaybackSnapshot.validated(invalid))
    }

    func testSnapshotClampsPositionWithoutRestartingFinishedTrack() throws {
        for (saved, expected) in [(-1.0, 0.0), (120_000, 120_000), (130_000, 120_000)] {
            var value = snapshot()
            value["position"] = saved
            XCTAssertEqual(try XCTUnwrap(RDPlaybackSnapshot.validated(value))["position"] as? Double, expected)
        }
    }

    @MainActor
    func testUnknownStreamDurationKeepsAbsolutePositionForRetry() throws {
        var value = snapshot()
        value["duration"] = 0.0
        value["position"] = 30_000.0
        let valid = try XCTUnwrap(RDPlaybackSnapshot.validated(value))
        XCTAssertEqual(valid["position"] as? Double, 30_000)
        let service = PlaybackService()
        service.configureReadyPlayback(valid)
        XCTAssertFalse(service.isPlaying)
        XCTAssertEqual(service.playedTime().intValue, 30_000)
        XCTAssertEqual(service.metadata.elapsedPlaybackTime, 30)
    }

    @MainActor
    func testSnapshotConfiguresNonFirstTrackPausedWithoutPlaybackNotifications() throws {
        let service = PlaybackService()
        var starts = 0
        let observer = NotificationCenter.default.addObserver(forName: Notification.Name(VLCPlaybackServicePlaybackDidStart),
                                                              object: service, queue: nil) { _ in starts += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        service.configureReadyPlayback(snapshot(shuffled: true))
        XCTAssertTrue(service.playerIsSetup)
        XCTAssertFalse(service.isPlaying)
        XCTAssertEqual(service.mediaList.count, 3)
        XCTAssertEqual(service.shuffledList.media(at: 0)?.metaData.title, "Track 2")
        XCTAssertEqual(service.currentlyPlayingMedia?.metaData.title, "Track 0")
        XCTAssertEqual(service.playbackPosition, 0.375, accuracy: 0.0001)
        XCTAssertEqual(service.playedTime().intValue, 45_000)
        XCTAssertEqual(service.metadata.elapsedPlaybackTime, 45)
        XCTAssertEqual(starts, 0)
    }

    @MainActor
    func testSnapshotDiskStopAndSeekRetainPausedQueue() throws {
        let url = RDPlaybackSnapshot.url
        let original = try? Data(contentsOf: url)
        defer {
            if let original { try? original.write(to: url, options: .atomic) }
            else { try? FileManager.default.removeItem(at: url) }
        }
        RDPlaybackSnapshot.save(snapshot())
        let service = PlaybackService()
        XCTAssertTrue(service.restoreReadyPlayback())
        XCTAssertFalse(service.isPlaying)
        service.jumpForward(15)
        XCTAssertEqual(service.playbackPosition, 0.5, accuracy: 0.0001)
        XCTAssertEqual(RDPlaybackSnapshot.readSnapshot()?["position"] as? Double, 60_000)
        service.stopPlayback()
        XCTAssertTrue(service.playerIsSetup)
        XCTAssertFalse(service.isPlaying)
        XCTAssertEqual(service.currentlyPlayingMedia?.metaData.title, "Track 1")
        XCTAssertEqual(service.playbackPosition, 0.5, accuracy: 0.0001)
        let relaunched = PlaybackService()
        XCTAssertTrue(relaunched.restoreReadyPlayback())
        XCTAssertFalse(relaunched.isPlaying)
        XCTAssertEqual(relaunched.playbackPosition, 0.5, accuracy: 0.0001)
        try Data("corrupt".utf8).write(to: url, options: .atomic)
        let corrupt = PlaybackService()
        XCTAssertTrue(corrupt.restoreReadyPlayback()) // handled without legacy resurrection
        XCTAssertFalse(corrupt.playerIsSetup)
        XCTAssertNil(corrupt.currentlyPlayingMedia)
    }

    @MainActor
    func testNewPlaybackConfigurationWinsOverDiskRestore() throws {
        let service = PlaybackService()
        service.configureReadyPlayback(snapshot())
        XCTAssertTrue(service.restoreReadyPlayback())
        XCTAssertEqual(service.currentlyPlayingMedia?.metaData.title, "Track 1")
        XCTAssertFalse(service.isPlaying)
    }

    @MainActor
    func testSnapshotRebuildsMissingLocalAndStreamedMediaWithoutOpeningThem() throws {
        var value = snapshot()
        var items = try XCTUnwrap(value["items"] as? [[String: Any]])
        items[1]["url"] = "file:///missing/track.mp3"
        value["items"] = items
        let list = try XCTUnwrap(RDPlaybackSnapshot.mediaList(value))
        XCTAssertEqual(list.count, 3)
        XCTAssertEqual(list.media(at: 1)?.url?.path, "/missing/track.mp3")
        XCTAssertEqual(DiscourseMediaFactory.identity(of: try XCTUnwrap(list.media(at: 1)))?.audioID, "audio-1")
        let service = PlaybackService()
        service.configureReadyPlayback(value)
        XCTAssertFalse(service.isPlaying)
        XCTAssertEqual(service.currentlyPlayingMedia?.metaData.title, "Track 1")
        XCTAssertEqual(service.playbackPosition, 0.375, accuracy: 0.0001)
    }

    @MainActor
    func testSnapshotResolvesVerifiedDownloadWithoutPlaying() throws {
        let audioID = "snapshot-test-\(UUID().uuidString)"
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1, 2, 3]).write(to: file)
        let downloads = DiscourseDownloadStore.shared
        try downloads.storeDownloadedFile(at: file, audioID: audioID, discourseID: "discourse")
        defer { _ = downloads.remove(audioID: audioID) }
        var value = snapshot()
        var items = try XCTUnwrap(value["items"] as? [[String: Any]])
        items[1]["audioID"] = audioID
        value["items"] = items
        let service = PlaybackService()
        service.configureReadyPlayback(value)
        XCTAssertEqual(service.currentlyPlayingMedia?.url, downloads.localURL(for: audioID))
        XCTAssertFalse(service.isPlaying)
        XCTAssertEqual(service.playbackPosition, 0.375, accuracy: 0.0001)
    }

    @MainActor
    func testNaturalCompletionRetainsFinalPositionPaused() throws {
        let snapshotURL = RDPlaybackSnapshot.url
        let original = try? Data(contentsOf: snapshotURL)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        defer {
            try? FileManager.default.removeItem(at: file)
            if let original { try? original.write(to: snapshotURL, options: .atomic) }
            else { try? FileManager.default.removeItem(at: snapshotURL) }
        }
        // A quarter-second of silence exercises the real VLC end-of-queue callback.
        var wav = Data("RIFF".utf8)
        func append(_ value: UInt32, bytes: Int = 4) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { wav.append(contentsOf: $0.prefix(bytes)) }
        }
        append(24_036)
        wav.append(Data("WAVEfmt ".utf8))
        append(16)
        append(1, bytes: 2)
        append(1, bytes: 2)
        append(48_000)
        append(96_000)
        append(2, bytes: 2)
        append(16, bytes: 2)
        wav.append(Data("data".utf8))
        append(24_000)
        wav.append(Data(count: 24_000))
        try wav.write(to: file)
        var value = snapshot()
        var item = try XCTUnwrap((value["items"] as? [[String: Any]])?.first)
        item["url"] = file.absoluteString
        item["duration"] = 250
        item["audioID"] = ""
        value["items"] = [item]
        value["index"] = 0
        value["position"] = 0.0
        value["duration"] = 250.0
        let service = PlaybackService()
        service.configureReadyPlayback(value)
        let stopped = expectation(description: "Finished queue retained")
        let observer = NotificationCenter.default.addObserver(forName: Notification.Name(VLCPlaybackServicePlaybackDidStop),
                                                              object: service, queue: .main) { _ in
            DispatchQueue.main.async {
                XCTAssertTrue(service.playerIsSetup)
                XCTAssertFalse(service.isPlaying)
                XCTAssertEqual(service.playbackPosition, 1, accuracy: 0.0001)
                stopped.fulfill()
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        service.play()
        wait(for: [stopped], timeout: 10)
        XCTAssertEqual(RDPlaybackSnapshot.readSnapshot()?["position"] as? Double, 250)
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
