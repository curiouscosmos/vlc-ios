/*****************************************************************************
 * DiscourseStoresTests.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * Unit coverage for the persistent stores: likes (seven-day refresh, optimistic
 * toggles, rollback, pending state), recently played (cap and dedupe), stats
 * dedupe, playback positions and progress, catalogue filters and the three-hour
 * weekly-stats cache.
 *****************************************************************************/

import XCTest
@testable import VLC

final class DiscourseStoresTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "discourse-stores-\(UUID().uuidString)"
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

    // MARK: - Likes

    func testLikesRefreshHonoursTheSevenDayWindow() async throws {
        var now = Date(timeIntervalSince1970: 1_000_000)
        let service = FakeLikeService()
        service.likes = DiscourseLikes(discourseIDs: ["d1"], audioIDs: ["a1"])
        let store = DiscourseLikesStore(settings: settings,
                                        service: service,
                                        dateProvider: { now },
                                        notificationCenter: NotificationCenter())

        XCTAssertFalse(store.hasCachedState)
        XCTAssertTrue(store.state.discourseIDs.isEmpty)

        try await store.refresh()
        XCTAssertEqual(store.state.discourseIDs, ["d1"])
        XCTAssertEqual(store.state.audioIDs, ["a1"])
        XCTAssertEqual(service.fetchCount, 1)
        XCTAssertTrue(store.hasCachedState)

        try await store.refresh()
        XCTAssertEqual(service.fetchCount, 1, "a second call inside the window must not hit the network")

        service.likes = DiscourseLikes(discourseIDs: ["d2"], audioIDs: [])
        now = now.addingTimeInterval(DiscourseLikesStore.refreshInterval + 1)
        try await store.refresh()
        XCTAssertEqual(service.fetchCount, 2)
        XCTAssertEqual(store.state.discourseIDs, ["d2"])

        try await store.refresh(force: true)
        XCTAssertEqual(service.fetchCount, 3)
    }

    func testOptimisticLikeAdoptsTheServerCount() async throws {
        let service = FakeLikeService()
        service.nextTotalLikes = 42
        let store = DiscourseLikesStore(settings: settings,
                                        service: service,
                                        notificationCenter: NotificationCenter())

        let change = try await store.toggleDiscourse(id: "d1", totalLikes: 10)
        XCTAssertEqual(change?.isLiked, true)
        XCTAssertEqual(change?.totalLikes, 42)
        XCTAssertTrue(store.isLiked(.discourse("d1")))
        XCTAssertEqual(store.count(for: .discourse("d1")), 42)
        XCTAssertFalse(store.isPending(.discourse("d1")))

        // Repeating the same request is a no-op while the state already matches.
        let repeatChange = try await store.setDiscourseLiked(true, id: "d1", totalLikes: 42)
        XCTAssertNil(repeatChange)
        XCTAssertEqual(service.discourseLikeCount, 1)

        // The membership is persisted for the next launch.
        let reloaded = DiscourseLikesStore(settings: settings,
                                           service: service,
                                           notificationCenter: NotificationCenter())
        XCTAssertTrue(reloaded.isLiked(.discourse("d1")))
    }

    func testUnlikeDecrementsAndSettles() async throws {
        let service = FakeLikeService()
        service.likes = DiscourseLikes(discourseIDs: [], audioIDs: ["a1"])
        service.nextTotalLikes = 3
        let store = DiscourseLikesStore(settings: settings,
                                        service: service,
                                        notificationCenter: NotificationCenter())
        try await store.refresh()

        let change = try await store.toggleAudio(id: "a1", totalLikes: 4)
        XCTAssertEqual(change?.isLiked, false)
        XCTAssertEqual(change?.totalLikes, 3)
        XCTAssertFalse(store.isLiked(.audio("a1")))
        XCTAssertEqual(service.audioUnlikeCount, 1)
    }

    func testFailedLikeRollsBack() async throws {
        let service = FakeLikeService()
        service.likeError = DiscourseAPIError.http(status: 500)
        let store = DiscourseLikesStore(settings: settings,
                                        service: service,
                                        notificationCenter: NotificationCenter())

        do {
            _ = try await store.setDiscourseLiked(true, id: "d1", totalLikes: 7)
            XCTFail("the failure must reach the caller so it can show the error copy")
        } catch {
            XCTAssertTrue(error is DiscourseAPIError)
        }

        XCTAssertFalse(store.isLiked(.discourse("d1")))
        XCTAssertNil(store.count(for: .discourse("d1")))
        XCTAssertFalse(store.isPending(.discourse("d1")))
        XCTAssertTrue(DiscourseLikesStore(settings: settings,
                                         service: service,
                                         notificationCenter: NotificationCenter()).state.discourseIDs.isEmpty)
    }

    func testPendingToggleIsRestoredAfterRelaunch() {
        settings.set(Set<String>(), forKey: DiscourseLikesStore.Keys.discourses)
        settings.set(Set<String>(), forKey: DiscourseLikesStore.Keys.audios)
        settings.set(Date().timeIntervalSince1970, forKey: DiscourseLikesStore.Keys.fetchedAt)
        settings.encode(["discourse:d9": true, "audio:a9": false],
                        forKey: DiscourseLikesStore.Keys.pending)

        let store = DiscourseLikesStore(settings: settings,
                                        service: FakeLikeService(),
                                        notificationCenter: NotificationCenter())

        XCTAssertTrue(store.isLiked(.discourse("d9")))
        XCTAssertTrue(store.isPending(.discourse("d9")))
        XCTAssertFalse(store.isLiked(.audio("a9")))
        XCTAssertTrue(store.isPending(.audio("a9")))
    }

    func testACompletedRefreshClearsPendingToggles() async throws {
        settings.encode(["discourse:d9": true], forKey: DiscourseLikesStore.Keys.pending)
        let service = FakeLikeService()
        service.likes = DiscourseLikes(discourseIDs: [], audioIDs: [])
        let store = DiscourseLikesStore(settings: settings,
                                        service: service,
                                        notificationCenter: NotificationCenter())

        try await store.refresh(force: true)
        XCTAssertFalse(store.isPending(.discourse("d9")))
        XCTAssertFalse(store.isLiked(.discourse("d9")))
    }

    func testPendingCountsSurviveListPayloadUpdates() async throws {
        let service = FakeLikeService()
        service.nextTotalLikes = 12
        let store = DiscourseLikesStore(settings: settings,
                                        service: service,
                                        notificationCenter: NotificationCenter())
        store.updateCount(5, for: .discourse("d1"))
        XCTAssertEqual(store.count(for: .discourse("d1")), 5)

        // While a toggle is pending, a list refresh must not undo the optimistic count.
        settings.encode(["discourse:d2": true], forKey: DiscourseLikesStore.Keys.pending)
        let pendingStore = DiscourseLikesStore(settings: settings,
                                              service: service,
                                              notificationCenter: NotificationCenter())
        pendingStore.updateCount(99, for: .discourse("d2"))
        XCTAssertNil(pendingStore.count(for: .discourse("d2")))
    }

    // MARK: - Like control state

    func testLikeStateUsesThePayloadUntilTheStoreKnowsACount() {
        let store = DiscourseLikesStore(settings: settings,
                                        service: FakeLikeService(),
                                        notificationCenter: NotificationCenter())

        let state = DiscourseLikeState.resolve(target: .discourse("d1"),
                                               payloadLikes: 7,
                                               store: store)
        XCTAssertEqual(state.count, 7)
        XCTAssertFalse(state.isLiked)
        XCTAssertFalse(state.isPending)
    }

    func testLikeStatePrefersTheStoredCountOverThePayload() {
        let store = DiscourseLikesStore(settings: settings,
                                        service: FakeLikeService(),
                                        notificationCenter: NotificationCenter())
        store.updateCount(9, for: .discourse("d1"))

        let state = DiscourseLikeState.resolve(target: .discourse("d1"),
                                               payloadLikes: 7,
                                               store: store)
        XCTAssertEqual(state.count, 9)
    }

    func testLikeStateReflectsTheLikedSets() async throws {
        let service = FakeLikeService()
        service.likes = DiscourseLikes(discourseIDs: ["d1"], audioIDs: ["a1"])
        let store = DiscourseLikesStore(settings: settings,
                                        service: service,
                                        notificationCenter: NotificationCenter())
        try await store.refresh()

        XCTAssertTrue(DiscourseLikeState.resolve(target: .discourse("d1"),
                                                 payloadLikes: 3,
                                                 store: store).isLiked)
        XCTAssertTrue(DiscourseLikeState.resolve(target: .audio("a1"),
                                                 payloadLikes: 0,
                                                 store: store).isLiked)
        XCTAssertFalse(DiscourseLikeState.resolve(target: .discourse("d2"),
                                                  payloadLikes: 3,
                                                  store: store).isLiked)
    }

    // MARK: - History

    func testHistoryDeduplicatesAndCapsAt24() {
        let store = DiscourseHistoryStore(settings: settings, notificationCenter: NotificationCenter())

        for index in 0..<30 {
            store.record(audio: Self.audio(id: "a\(index)"))
        }

        let items = store.recentlyPlayedAudios
        XCTAssertEqual(items.count, DiscourseHistoryStore.limit)
        XCTAssertEqual(items.first?.id, "a29")
        XCTAssertEqual(Set(items.map(\.id)).count, items.count)

        store.record(audio: Self.audio(id: "a10"))
        XCTAssertEqual(store.recentlyPlayedAudios.first?.id, "a10")
        XCTAssertEqual(store.recentlyPlayedAudios.count, DiscourseHistoryStore.limit)

        let reloaded = DiscourseHistoryStore(settings: settings, notificationCenter: NotificationCenter())
        XCTAssertEqual(reloaded.recentlyPlayedAudios.first?.id, "a10")
        XCTAssertEqual(reloaded.recentlyPlayedAudios.count, DiscourseHistoryStore.limit)
    }

    func testDiscourseHistoryIsRecordedSeparately() {
        let store = DiscourseHistoryStore(settings: settings, notificationCenter: NotificationCenter())
        store.record(discourse: Self.discourse(id: "d1"))
        store.record(discourse: Self.discourse(id: "d2"))
        store.record(discourse: Self.discourse(id: "d1"))

        XCTAssertEqual(store.recentlyPlayedDiscourses.map(\.id), ["d1", "d2"])
        XCTAssertTrue(store.recentlyPlayedAudios.isEmpty)

        store.removeAll()
        XCTAssertTrue(store.recentlyPlayedDiscourses.isEmpty)
    }

    // MARK: - Stats dedupe

    func testStatsDedupeForTwentyFourHours() {
        let store = DiscourseStatsStore(settings: settings)
        let now = Date(timeIntervalSince1970: 5_000_000)

        XCTAssertTrue(store.shouldSend(audioID: "a1", now: now))
        store.markSent(audioID: "a1", at: now)
        XCTAssertFalse(store.shouldSend(audioID: "a1", now: now.addingTimeInterval(60)))
        XCTAssertTrue(store.shouldSend(audioID: "a2", now: now))

        // The dedupe index survives a relaunch.
        let reloaded = DiscourseStatsStore(settings: settings)
        XCTAssertFalse(reloaded.shouldSend(audioID: "a1", now: now))

        // Once the window elapses the entry is pruned and the track reports again.
        XCTAssertTrue(reloaded.shouldSend(audioID: "a1", now: now.addingTimeInterval(DiscourseStatsStore.retention + 1)))
    }

    func testStatsCleanupDropsExpiredEntries() {
        let store = DiscourseStatsStore(settings: settings)
        let now = Date(timeIntervalSince1970: 6_000_000)
        store.markSent(audioID: "a1", at: now)
        store.cleanup(now: now.addingTimeInterval(DiscourseStatsStore.retention + 1))
        XCTAssertFalse(settings.contains(DiscourseStatsStore.Keys.sent))
    }

    // MARK: - Playback

    func testPlaybackPositionsFractionsAndCompletion() {
        let store = DiscoursePlaybackStore(settings: settings, notificationCenter: NotificationCenter())
        store.register(id: "a1", discourseID: "d1", durationMilliseconds: 100_000)

        XCTAssertNil(store.position(audioID: "a1"))
        XCTAssertEqual(store.fraction(audioID: "a1"), 0)

        store.savePosition(25_000, audioID: "a1")
        XCTAssertEqual(store.position(audioID: "a1"), 25_000)
        XCTAssertEqual(store.fraction(audioID: "a1"), 0.25, accuracy: 0.0001)

        store.markCompleted(audioID: "a1")
        XCTAssertTrue(store.isCompleted(audioID: "a1"))
        XCTAssertEqual(store.fraction(audioID: "a1"), 1)

        // Replaying from the start clears the completed flag.
        store.savePosition(500, audioID: "a1")
        XCTAssertFalse(store.isCompleted(audioID: "a1"))
        XCTAssertEqual(store.fraction(audioID: "a1"), 0.005, accuracy: 0.0001)

        store.clearProgress(audioID: "a1")
        XCTAssertNil(store.position(audioID: "a1"))
        XCTAssertEqual(store.fraction(audioID: "a1"), 0)

        // Positions persist for the next launch.
        store.savePosition(50_000, audioID: "a1")
        let reloaded = DiscoursePlaybackStore(settings: settings, notificationCenter: NotificationCenter())
        XCTAssertEqual(reloaded.position(audioID: "a1"), 50_000)
        XCTAssertEqual(reloaded.fraction(audioID: "a1"), 0.5, accuracy: 0.0001)
    }

    func testDiscourseFractionAveragesKnownTracks() {
        let store = DiscoursePlaybackStore(settings: settings, notificationCenter: NotificationCenter())
        let tracks = [Self.audio(id: "a1", discourseID: "d1", durationSeconds: 100),
                      Self.audio(id: "a2", discourseID: "d1", durationSeconds: 100)]
        store.register(tracks, discourseID: "d1")

        store.savePosition(50_000, audioID: "a1")
        store.markCompleted(audioID: "a2")

        XCTAssertEqual(store.discourseFraction(discourseID: "d1", trackCount: 2), 0.75, accuracy: 0.0001)
        XCTAssertEqual(store.discourseFraction(discourseID: "d1"), 0.75, accuracy: 0.0001)
        XCTAssertEqual(store.discourseFraction(discourseID: "d1", trackCount: 4), 0.375, accuracy: 0.0001)
    }

    func testRegisteringTracksDropsRemovedOnes() {
        let store = DiscoursePlaybackStore(settings: settings, notificationCenter: NotificationCenter())
        store.register([Self.audio(id: "a1", discourseID: "d1"),
                        Self.audio(id: "a2", discourseID: "d1")],
                       discourseID: "d1")
        XCTAssertEqual(store.discourseFraction(discourseID: "d1", trackCount: 2), 0, accuracy: 0.0001)

        store.register([Self.audio(id: "a1", discourseID: "d1")], discourseID: "d1")
        XCTAssertNotNil(store.trackInfo(for: "a1"))
        XCTAssertNil(store.trackInfo(for: "a2"))

        // Tracks of other discourses are untouched.
        store.register([Self.audio(id: "b1", discourseID: "d2")], discourseID: "d2")
        store.register([Self.audio(id: "a1", discourseID: "d1")], discourseID: "d1")
        XCTAssertNotNil(store.trackInfo(for: "b1"))
    }

    func testPlayedFlagRoundTrips() {
        let store = DiscoursePlaybackStore(settings: settings, notificationCenter: NotificationCenter())
        XCTAssertFalse(store.isPlayed(audioID: "a1"))
        store.markPlayed(audioID: "a1")
        XCTAssertTrue(store.isPlayed(audioID: "a1"))
        XCTAssertTrue(DiscoursePlaybackStore(settings: settings, notificationCenter: NotificationCenter()).isPlayed(audioID: "a1"))

        store.clearPlayed(audioID: "a1")
        XCTAssertFalse(store.isPlayed(audioID: "a1"))
    }

    // MARK: - Catalogue filters

    func testCatalogueFiltersRoundTrip() {
        let store = DiscourseCatalogueFilterStore(settings: settings)
        XCTAssertNil(store.language)
        XCTAssertNil(store.sort)
        XCTAssertFalse(store.hasActiveFilters)

        store.save(language: .hindi, sort: .mostLiked)
        XCTAssertEqual(store.language, .hindi)
        XCTAssertEqual(store.sort, .mostLiked)
        XCTAssertTrue(store.hasActiveFilters)

        let reloaded = DiscourseCatalogueFilterStore(settings: settings)
        XCTAssertEqual(reloaded.language, .hindi)
        XCTAssertEqual(reloaded.sort, .mostLiked)

        store.reset()
        XCTAssertFalse(store.hasActiveFilters)
    }

    func testUnknownFilterValuesReadAsNoFilter() {
        settings.set("klingon", forKey: DiscourseCatalogueFilterStore.Keys.language)
        settings.set("newest", forKey: DiscourseCatalogueFilterStore.Keys.sort)
        let store = DiscourseCatalogueFilterStore(settings: settings)
        XCTAssertNil(store.language)
        XCTAssertNil(store.sort)
    }

    // MARK: - Weekly stats cache

    func testStatsCacheHonoursThreeHourTTLAndServesStaleOnFailure() async throws {
        var now = Date(timeIntervalSince1970: 9_000_000)
        let service = FakeStatsService()
        service.discourses = [Self.discourse(id: "d1")]
        service.audios = [Self.audio(id: "a1")]
        let cache = DiscourseStatsCache(settings: settings, service: service, dateProvider: { now })

        let first = try await cache.discourses()
        XCTAssertEqual(first.map(\.id), ["d1"])
        XCTAssertEqual(service.discourseCalls, 1)
        let firstAudios = try await cache.audios()
        XCTAssertEqual(firstAudios.map(\.id), ["a1"])
        XCTAssertEqual(service.audioCalls, 1)

        _ = try await cache.discourses()
        _ = try await cache.audios()
        XCTAssertEqual(service.discourseCalls, 1, "fresh entries must not hit the network")
        XCTAssertEqual(service.audioCalls, 1)

        now = now.addingTimeInterval(DiscourseStatsCache.timeToLive + 1)
        _ = try await cache.discourses()
        XCTAssertEqual(service.discourseCalls, 2, "entries expire after three hours")
        XCTAssertEqual(service.lastForceRefresh, true,
                       "refreshing must bypass the API layer's 24 h cache")

        service.discourses = [Self.discourse(id: "d2")]
        let forced = try await cache.discourses(forceRefresh: true)
        XCTAssertEqual(forced.map(\.id), ["d2"])
        XCTAssertEqual(service.discourseCalls, 3)

        service.error = DiscourseAPIError.http(status: 500)
        now = now.addingTimeInterval(DiscourseStatsCache.timeToLive + 1)
        let fallback = try await cache.discourses()
        XCTAssertEqual(fallback.map(\.id), ["d2"], "a failed refresh keeps the previous list")
        XCTAssertEqual(service.discourseCalls, 4)
        XCTAssertEqual(cache.cachedDiscourses()?.map(\.id), ["d2"],
                       "the stale payload is available for an SWR first render")
    }

    func testStatsCachePropagatesFailureWithoutCachedCopy() async {
        let service = FakeStatsService()
        service.error = DiscourseAPIError.http(status: 500)
        let cache = DiscourseStatsCache(settings: settings, service: service, dateProvider: Date.init)

        do {
            _ = try await cache.discourses()
            XCTFail("a failure with no cached list must reach the caller")
        } catch {
            XCTAssertTrue(error is DiscourseAPIError)
        }
    }

    func testStatsCacheAlwaysFetchesOtherWindows() async throws {
        let service = FakeStatsService()
        let cache = DiscourseStatsCache(settings: settings, service: service, dateProvider: Date.init)

        _ = try await cache.discourses(window: .last24Hours)
        _ = try await cache.discourses(window: .last24Hours)
        XCTAssertEqual(service.discourseCalls, 2, "only the weekly window is cached")
    }

    // MARK: - Fixtures

    private static func discourse(id: String) -> Discourse {
        Discourse(id: id, title: "Discourse \(id)")
    }

    private static func audio(id: String,
                              discourseID: String = "d1",
                              durationSeconds: Double? = 60) -> DiscourseAudio {
        DiscourseAudio(id: id,
                       discourseID: discourseID,
                       discourseName: "Discourse \(discourseID)",
                       title: "Track \(id)",
                       audioURLString: "https://osho.b-cdn.net/OSHO/\(id).mp3",
                       durationSeconds: durationSeconds)
    }

    // MARK: - Fakes

    private final class FakeLikeService: DiscourseLikeService {
        var likes = DiscourseLikes()
        var fetchCount = 0
        var fetchError: Error?
        var likeError: Error?
        var unlikeError: Error?
        var nextTotalLikes = 0
        private(set) var discourseLikeCount = 0
        private(set) var discourseUnlikeCount = 0
        private(set) var audioLikeCount = 0
        private(set) var audioUnlikeCount = 0

        func fetchLikes() async throws -> DiscourseLikes {
            fetchCount += 1
            if let fetchError {
                throw fetchError
            }
            return likes
        }

        func sendDiscourseLike(id: String) async throws -> DiscourseLikeResult {
            discourseLikeCount += 1
            if let likeError {
                throw likeError
            }
            return DiscourseLikeResult(discourseID: id, liked: true, totalLikes: nextTotalLikes)
        }

        func sendDiscourseUnlike(id: String) async throws -> DiscourseUnlikeResult {
            discourseUnlikeCount += 1
            if let unlikeError {
                throw unlikeError
            }
            return DiscourseUnlikeResult(discourseID: id, unliked: true, totalLikes: nextTotalLikes)
        }

        func sendAudioLike(id: String) async throws -> DiscourseLikeResult {
            audioLikeCount += 1
            if let likeError {
                throw likeError
            }
            return DiscourseLikeResult(audioID: id, liked: true, totalLikes: nextTotalLikes)
        }

        func sendAudioUnlike(id: String) async throws -> DiscourseUnlikeResult {
            audioUnlikeCount += 1
            if let unlikeError {
                throw unlikeError
            }
            return DiscourseUnlikeResult(audioID: id, unliked: true, totalLikes: nextTotalLikes)
        }
    }

    private final class FakeStatsService: DiscourseStatsService {
        var discourses: [Discourse] = []
        var audios: [DiscourseAudio] = []
        var error: Error?
        private(set) var discourseCalls = 0
        private(set) var audioCalls = 0
        private(set) var lastForceRefresh: Bool?

        func fetchDiscourseStats(window: DiscourseStatsWindow,
                                 forceRefresh: Bool) async throws -> [Discourse] {
            discourseCalls += 1
            lastForceRefresh = forceRefresh
            if let error {
                throw error
            }
            return discourses
        }

        func fetchAudioStats(window: DiscourseStatsWindow,
                             forceRefresh: Bool) async throws -> [DiscourseAudio] {
            audioCalls += 1
            lastForceRefresh = forceRefresh
            if let error {
                throw error
            }
            return audios
        }
    }
}
