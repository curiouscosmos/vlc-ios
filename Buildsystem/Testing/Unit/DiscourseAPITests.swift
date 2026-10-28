/*****************************************************************************
 * DiscourseAPITests.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * Coverage for the discourse API layer: payload decoding, URL resolution,
 * cache policy and error mapping. These tests build the watch-embedded
 * `VLC-iOS` host, so running them needs a watchOS simulator runtime
 * (see AGENTS.md section 10.8).
 *****************************************************************************/

import XCTest
@testable import VLC

final class DiscourseAPITests: XCTestCase {
    // MARK: - Catalogue decoding

    func testDecodesDiscoursePage() throws {
        let page = try JSONDecoder().decode(DiscoursePage<Discourse>.self, from: Self.discoursesJSON)

        XCTAssertEqual(page.data.count, 2)
        XCTAssertEqual(page.meta.page, 2)
        XCTAssertEqual(page.meta.pageSize, 16)
        XCTAssertEqual(page.meta.totalRecords, 31)
        XCTAssertEqual(page.meta.totalPages, 2)
        XCTAssertNil(page.data[0].thumbnailURLString)
        XCTAssertEqual(page.data[0].totalTracks, 42)
        XCTAssertEqual(page.data[0].totalLikes, 1203)
        XCTAssertNil(page.data[0].plays, "catalogue payloads do not carry plays")
        XCTAssertEqual(page.data[1].thumbnailURL?.absoluteString,
                       "https://osho.b-cdn.net/OSHO/covers/secrets.jpg")
    }

    func testDecodesTracksDefensively() throws {
        let envelope = try JSONDecoder().decode(DiscourseAudiosEnvelope.self, from: Self.tracksJSON)

        XCTAssertEqual(envelope.meta.totalRecords, 2)
        XCTAssertEqual(envelope.data[0].audioURL?.absoluteString, "https://media.example.com/a1.mp3")
        XCTAssertEqual(envelope.data[0].durationMilliseconds, 1_234_500)
        XCTAssertEqual(envelope.data[0].trackNumber, 3)
        XCTAssertEqual(envelope.data[0].mimeType, "audio/mpeg")
        XCTAssertNil(envelope.data[1].durationMilliseconds)
        XCTAssertEqual(envelope.data[1].audioURL?.absoluteString,
                       "https://osho.b-cdn.net/OSHO/tracks/a2.mp3")
        XCTAssertTrue(envelope.data[1].language.isEmpty)
        XCTAssertNil(envelope.data[1].fileSize)
    }

    func testDecodesStatsPayload() throws {
        let stats = try JSONDecoder().decode(DiscourseStatsListEnvelope<Discourse>.self, from: Self.statsJSON)
        XCTAssertEqual(stats.data.count, 1)
        XCTAssertEqual(stats.data[0].playCount, 12)
    }

    func testDecodesLikesPayloads() throws {
        let likes = try JSONDecoder().decode(DiscourseLikes.self, from: Self.likesJSON)
        XCTAssertEqual(likes.discourseIDs, ["d1", "d2"])
        XCTAssertEqual(likes.audioIDs, ["a1"])

        let empty = try JSONDecoder().decode(DiscourseLikes.self, from: Data("{}".utf8))
        XCTAssertTrue(empty.discourseIDs.isEmpty)
        XCTAssertTrue(empty.audioIDs.isEmpty)

        let like = try JSONDecoder().decode(DiscourseLikeEnvelope.self, from: Self.likeJSON).data
        XCTAssertTrue(like.liked)
        XCTAssertEqual(like.totalLikes, 77)
        XCTAssertEqual(like.discourseID, "d1")

        let unlike = try JSONDecoder().decode(DiscourseUnlikeEnvelope.self, from: Self.unlikeJSON).data
        XCTAssertTrue(unlike.unliked)
        XCTAssertEqual(unlike.totalLikes, 4)
        XCTAssertEqual(unlike.audioID, "a1")
    }

    // MARK: - URL resolution

    func testAbsoluteHTTPSURLsAreKept() {
        XCTAssertEqual(DiscourseURLResolver.resolve("https://osho.b-cdn.net/OSHO/x.mp3")?.absoluteString,
                       "https://osho.b-cdn.net/OSHO/x.mp3")
        XCTAssertEqual(DiscourseURLResolver.resolve("  https://a.example/b.mp3 \n")?.absoluteString,
                       "https://a.example/b.mp3")
    }

    func testRelativePathsResolveAgainstTheCDN() {
        XCTAssertEqual(DiscourseURLResolver.resolve("/A Bird on the Wing /A_Bird_01.mp3")?.absoluteString,
                       "https://osho.b-cdn.net/OSHO/A%20Bird%20on%20the%20Wing%20/A_Bird_01.mp3")
        XCTAssertEqual(DiscourseURLResolver.resolve("A%20Bird/A_Bird_01.mp3")?.absoluteString,
                       "https://osho.b-cdn.net/OSHO/A%20Bird/A_Bird_01.mp3",
                       "existing percent escapes must not be escaped twice")
        XCTAssertEqual(DiscourseURLResolver.resolve("/covers/a.jpg")?.absoluteString,
                       "https://osho.b-cdn.net/OSHO/covers/a.jpg")
    }

    func testUnsupportedValuesAreRejected() {
        XCTAssertNil(DiscourseURLResolver.resolve("http://insecure.example/a.mp3"))
        XCTAssertNil(DiscourseURLResolver.resolve("file:///etc/passwd"))
        XCTAssertNil(DiscourseURLResolver.resolve("data:audio/mpeg;base64,AAAA"))
        XCTAssertNil(DiscourseURLResolver.resolve("escher:foo"))
        XCTAssertNil(DiscourseURLResolver.resolve(""))
        XCTAssertNil(DiscourseURLResolver.resolve("   "))
        XCTAssertNil(DiscourseURLResolver.resolve(nil))
    }

    // MARK: - Cache

    func testCacheHonoursTheTimeToLive() throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var now = Date(timeIntervalSince1970: 1_000_000)
        let cache = DiscourseAPICache(directory: directory, dateProvider: { now })
        let url = try XCTUnwrap(URL(string: "https://oshoapi.example/discourses?page=1"))
        let otherURL = try XCTUnwrap(URL(string: "https://oshoapi.example/discourses?page=2"))

        cache.store(Data("first".utf8), for: url)
        XCTAssertEqual(cache.freshData(for: url), Data("first".utf8))
        XCTAssertNil(cache.staleData(for: otherURL), "each URL is a separate entry")

        now = now.addingTimeInterval(DiscourseAPICache.timeToLive - 1)
        XCTAssertNotNil(cache.freshData(for: url), "entry is fresh just before the TTL")

        now = now.addingTimeInterval(2)
        XCTAssertNil(cache.freshData(for: url))
        XCTAssertEqual(cache.staleData(for: url), Data("first".utf8), "stale entries stay readable for fallbacks")

        cache.store(Data("second".utf8), for: url)
        XCTAssertEqual(cache.freshData(for: url), Data("second".utf8))

        cache.removeAll()
        XCTAssertNil(cache.staleData(for: url))
    }

    func testStaleCachedCatalogueAndTrackListsAreAvailableForSWR() throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var now = Date(timeIntervalSince1970: 3_000_000)
        let cache = DiscourseAPICache(directory: directory, dateProvider: { now })
        let client = DiscourseAPIClient(apiKey: "test-key",
                                        baseURLString: "https://oshoapi.example/",
                                        cache: cache)

        let catalogueURL = try XCTUnwrap(URL(string: "https://oshoapi.example/discourses?page=1"))
        let tracksURL = try XCTUnwrap(URL(string: "https://oshoapi.example/discourse-audios?discourse_id=d1"))
        cache.store(Self.discoursesJSON, for: catalogueURL)
        cache.store(Self.tracksJSON, for: tracksURL)

        now = now.addingTimeInterval(DiscourseAPICache.timeToLive + 1)
        XCTAssertNil(cache.freshData(for: catalogueURL))
        XCTAssertEqual(client.cachedDiscourses(page: 1)?.data.count, 2)
        XCTAssertEqual(client.cachedDiscourseTracks(discourseID: "d1")?.count, 2)
    }

    func testCacheEvictsOldestEntriesPastCapacity() {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var now = Date(timeIntervalSince1970: 2_000_000)
        let cache = DiscourseAPICache(directory: directory, dateProvider: { now })
        var urls: [URL] = []
        let payload = Data(repeating: 7, count: 3 * 1024 * 1024)

        for index in 0..<6 {
            guard let url = URL(string: "https://oshoapi.example/big?page=\(index)") else {
                return XCTFail("could not build the test URL")
            }
            urls.append(url)
            now = now.addingTimeInterval(60)
            cache.store(payload, for: url)
        }

        let survivors = urls.filter { cache.staleData(for: $0) != nil }
        XCTAssertLessThanOrEqual(survivors.count, 4)
        XCTAssertNotNil(cache.staleData(for: urls[5]), "the newest entry survives")
        XCTAssertNil(cache.staleData(for: urls[0]), "the oldest entry is evicted")
    }

    // MARK: - Errors

    func testErrorClassificationAndCopy() {
        XCTAssertTrue(DiscourseAPIError.http(status: 500).isConnectivityFailure)
        XCTAssertFalse(DiscourseAPIError.http(status: 404).isConnectivityFailure)
        XCTAssertTrue(DiscourseAPIError.offline(nil).isConnectivityFailure)
        XCTAssertFalse(DiscourseAPIError.cancelled.isConnectivityFailure)
        XCTAssertEqual(DiscourseAPIError.http(status: 500).userMessage, "Failed to communicate with the server.")
        XCTAssertEqual(DiscourseErrorCopy.likeFailure, "Could not update your like. Tap the heart to try again.")
    }

    func testDiagnosticsDoNotLeakPayloadDetails() {
        let error = DiscourseAPIError.decoding(DecodingError.valueNotFound(Int.self,
                                                                           .init(codingPath: [],
                                                                                 debugDescription: "secret")))
        XCTAssertEqual(error.diagnosticDescription, "decoding failed (DecodingError)")
        XCTAssertFalse(error.diagnosticDescription.contains("secret"))
    }

    // MARK: - Identity

    func testIdentityUUIDValidation() {
        XCTAssertTrue(DiscourseIdentity.isUUID("105fe511-ed2e-4ce1-be4d-4b1c701fa94e"))
        XCTAssertTrue(DiscourseIdentity.isUUID(UUID().uuidString))
        XCTAssertFalse(DiscourseIdentity.isUUID("not-a-uuid"))
        XCTAssertFalse(DiscourseIdentity.isUUID(""))
    }

    // MARK: - Fixtures

    private static func temporaryDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("discourse-cache-\(UUID().uuidString)", isDirectory: true)
    }

    private static let discoursesJSON = Data("""
    {
      "data": [
        {
          "id": "d1",
          "title": "Adhyatam Upanishad",
          "thumbnail_url": null,
          "is_audio_cleaned": true,
          "language": "hindi",
          "total_tracks": 42,
          "total_likes": 1203,
          "slug": null,
          "created_at": "2026-01-01T00:00:00.000Z",
          "updated_at": "2026-01-02T00:00:00.000Z"
        },
        {
          "id": "d2",
          "title": "The Book of Secrets",
          "thumbnail_url": "covers/secrets.jpg",
          "is_audio_cleaned": false,
          "language": "english",
          "total_tracks": 80,
          "total_likes": 9,
          "slug": "the-book-of-secrets",
          "created_at": "2026-01-01T00:00:00.000Z",
          "updated_at": "2026-01-02T00:00:00.000Z"
        }
      ],
      "meta": { "page": 2, "page_size": 16, "total_records": 31, "total_pages": 2 }
    }
    """.utf8)

    private static let tracksJSON = Data("""
    {
      "data": [
        {
          "id": "a1",
          "discourse_id": "d1",
          "discourse_name": "Adhyatam Upanishad",
          "discourse_thumbnail_url": "covers/upanishad.jpg",
          "language": "hindi",
          "title": "The Art of Listening",
          "audio_url": "https://media.example.com/a1.mp3",
          "duration_seconds": 1234.5,
          "file_size": 9876543,
          "mime_type": "audio/mpeg",
          "track_number": 3,
          "total_likes": 17,
          "created_at": "2026-01-01T00:00:00.000Z",
          "updated_at": "2026-01-02T00:00:00.000Z"
        },
        {
          "id": "a2",
          "discourse_id": "d1",
          "discourse_name": "Adhyatam Upanishad",
          "title": "Second Track",
          "audio_url": "tracks/a2.mp3",
          "duration_seconds": null,
          "track_number": null,
          "total_likes": 0
        }
      ],
      "meta": { "total_records": 2 }
    }
    """.utf8)

    private static let statsJSON = Data("""
    { "data": [ { "id": "d1", "title": "Adhyatam", "language": "hindi", "plays": 12 } ],
      "meta": { "by": "discourse", "time": "7_days", "limit": 16 } }
    """.utf8)

    private static let likesJSON = Data("""
    { "discourse": ["d1", "d2"], "discourse_audio": ["a1"] }
    """.utf8)

    private static let likeJSON = Data("""
    { "data": { "discourse_id": "d1", "liked_by_user_id": "u", "liked": true, "total_likes": 77 } }
    """.utf8)

    private static let unlikeJSON = Data("""
    { "data": { "discourse_audio_id": "a1", "liked_by_user_id": "u", "unliked": true, "total_likes": 4 } }
    """.utf8)
}
