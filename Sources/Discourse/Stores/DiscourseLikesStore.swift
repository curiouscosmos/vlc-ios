/*****************************************************************************
 * DiscourseLikesStore.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * Anonymous, optimistic likes. The user is identified by the install UUID, so
 * the server state belongs to this device: `GET /likes` is refreshed at most
 * once every seven days (on foreground/resume), never from cache.
 *
 * Toggling is optimistic. A tap updates the sets and the count immediately, and
 * the request settles in the background:
 *   - success reconciles the total without reversing the optimistic change;
 *   - any failure restores the previous membership and count, then rethrows so
 *     the caller can show the spec's copy.
 * Pending targets are persisted, so an app killed mid-request still shows the
 * state the user asked for until the next refresh reconciles it.
 *****************************************************************************/

import Foundation

// MARK: - Service seam

/// The like routes the store needs. `DiscourseAPIClient` is the production
/// implementation; tests inject a fake.
protocol DiscourseLikeService {
    func fetchLikes() async throws -> DiscourseLikes
    func sendDiscourseLike(id: String) async throws -> DiscourseLikeResult
    func sendDiscourseUnlike(id: String) async throws -> DiscourseUnlikeResult
    func sendAudioLike(id: String) async throws -> DiscourseLikeResult
    func sendAudioUnlike(id: String) async throws -> DiscourseUnlikeResult
}

extension DiscourseAPIClient: DiscourseLikeService {
    func fetchLikes() async throws -> DiscourseLikes {
        try await likes()
    }

    func sendDiscourseLike(id: String) async throws -> DiscourseLikeResult {
        try await likeDiscourse(id: id)
    }

    func sendDiscourseUnlike(id: String) async throws -> DiscourseUnlikeResult {
        try await unlikeDiscourse(id: id)
    }

    func sendAudioLike(id: String) async throws -> DiscourseLikeResult {
        try await likeAudio(id: id)
    }

    func sendAudioUnlike(id: String) async throws -> DiscourseUnlikeResult {
        try await unlikeAudio(id: id)
    }
}

// MARK: - Store

final class DiscourseLikesStore {
    /// A discourse or a track. Ids are independent between the two kinds.
    struct Target: Hashable {
        let id: String
        let isAudio: Bool

        static func discourse(_ id: String) -> Target {
            Target(id: id, isAudio: false)
        }

        static func audio(_ id: String) -> Target {
            Target(id: id, isAudio: true)
        }

        init(id: String, isAudio: Bool) {
            self.id = id
            self.isAudio = isAudio
        }

        /// Stable representation used in the persisted pending map.
        var storageKey: String {
            (isAudio ? "audio:" : "discourse:") + id
        }

        init?(storageKey: String) {
            if storageKey.hasPrefix("audio:") {
                id = String(storageKey.dropFirst("audio:".count))
                isAudio = true
            } else if storageKey.hasPrefix("discourse:") {
                id = String(storageKey.dropFirst("discourse:".count))
                isAudio = false
            } else {
                return nil
            }
            if id.isEmpty {
                return nil
            }
        }
    }

    struct State {
        fileprivate(set) var discourseIDs: Set<String> = []
        fileprivate(set) var audioIDs: Set<String> = []
        /// Target -> requested membership while the request is in flight.
        fileprivate(set) var pending: [Target: Bool] = [:]
        /// Known counts, keyed by target. Populated from list payloads and likes.
        fileprivate(set) var counts: [Target: Int] = [:]

        func isLiked(_ target: Target) -> Bool {
            target.isAudio ? audioIDs.contains(target.id) : discourseIDs.contains(target.id)
        }

        func count(for target: Target) -> Int? {
            counts[target]
        }

        func isPending(_ target: Target) -> Bool {
            pending[target] != nil
        }

        fileprivate mutating func insert(_ target: Target) {
            if target.isAudio {
                audioIDs.insert(target.id)
            } else {
                discourseIDs.insert(target.id)
            }
        }

        fileprivate mutating func remove(_ target: Target) {
            if target.isAudio {
                audioIDs.remove(target.id)
            } else {
                discourseIDs.remove(target.id)
            }
        }
    }

    struct Change {
        let target: Target
        let isLiked: Bool
        let totalLikes: Int
    }

    enum Keys {
        static let discourses = "osho_api_liked_discourses"
        static let audios = "osho_api_liked_audios"
        static let fetchedAt = "osho_api_likes_fetched_at"
        static let pending = "osho_api_likes_pending"
    }

    /// The likes of one install are refreshed once a week.
    static let refreshInterval: TimeInterval = 7 * 24 * 60 * 60

    static let shared = DiscourseLikesStore()

    private let settings: DiscourseSettings
    private let service: DiscourseLikeService
    private let resolver: ([String], [String]) async throws -> DiscourseAPIClient.FavouriteResolution
    private let dateProvider: () -> Date
    private let notificationCenter: NotificationCenter
    private let queue = DispatchQueue(label: "online.sandalbar.rajneesh-discourse.likes")
    private var inFlight: Set<Target> = []
    private var confirmedCounts: Set<Target> = []
    private var revision = 0
    private var stateStore: State

    init(settings: DiscourseSettings = .shared,
         service: DiscourseLikeService = DiscourseAPIClient.shared,
         resolver: @escaping ([String], [String]) async throws -> DiscourseAPIClient.FavouriteResolution = { try await DiscourseAPIClient.shared.resolveFavourites(discourses: $0, audios: $1) },
         dateProvider: @escaping () -> Date = Date.init,
         notificationCenter: NotificationCenter = .default) {
        self.settings = settings
        self.service = service
        self.resolver = resolver
        self.dateProvider = dateProvider
        self.notificationCenter = notificationCenter

        var state = State()
        state.discourseIDs = settings.stringSet(Keys.discourses)
        state.audioIDs = settings.stringSet(Keys.audios)
        let pending = settings.decode([String: Bool].self, forKey: Keys.pending) ?? [:]
        for (key, liked) in pending {
            guard let target = Target(storageKey: key) else {
                continue
            }
            state.pending[target] = liked
            if liked {
                state.insert(target)
            } else {
                state.remove(target)
            }
        }
        stateStore = state
        // No write-back here: `UserDefaults` merges the volatile argument domain,
        // so persisting at launch would promote UI-test launch arguments (and any
        // other temporary override) into the durable liked sets.
    }

    struct FavouriteMetadata: Codable {
        var discourses: [String: Discourse] = [:]
        var audios: [String: DiscourseAudio] = [:]
        var added: [String: Date] = [:]
        var refreshed: [String: Date] = [:]
        var unavailable: Set<String> = []
        var created: Set<String> = []
    }

    enum Collection: String, CaseIterable {
        case tracks = "favourite-tracks"
        case discourses = "favourite-discourses"
        var title: String {
            self == .tracks ? NSLocalizedString("Favourite Tracks", comment: "Automatic playlist")
                : NSLocalizedString("Favourite Discourses", comment: "Automatic playlist")
        }
    }

    private static let metadataKey = "osho_api_favourite_metadata"

    var favouriteMetadata: FavouriteMetadata {
        queue.sync { settings.decode(FavouriteMetadata.self, forKey: Self.metadataKey) ?? FavouriteMetadata() }
    }

    func favouriteIDs(in collection: Collection) -> [String] {
        let state = self.state
        let metadata = favouriteMetadata
        return (collection == .tracks ? state.audioIDs : state.discourseIDs).sorted {
            let prefix = collection == .tracks ? "audio:" : "discourse:"
            let left = metadata.added[prefix + $0] ?? .distantPast
            let right = metadata.added[prefix + $1] ?? .distantPast
            return left == right ? $0 < $1 : left > right
        }
    }

    /// A collection earns a row on the Playlists tab only while at least one of
    /// its items has a saved payload to render. A liked id whose metadata has
    /// not been recovered yet has no title, artwork or duration, so showing the
    /// collection would leave an apparently empty row on screen; it reappears
    /// as soon as `refreshFavourites()` restores the payload. Counts and
    /// membership are unaffected by this display decision.
    func hasPresentableFavourites(in collection: Collection) -> Bool {
        let state = self.state
        let metadata = favouriteMetadata
        let ids = collection == .tracks ? state.audioIDs : state.discourseIDs
        return ids.contains { id in
            collection == .tracks ? metadata.audios[id] != nil : metadata.discourses[id] != nil
        }
    }

    func capture(discourse: Discourse? = nil, audio: DiscourseAudio? = nil, fresh: Bool = true) {
        queue.sync {
            var metadata = settings.decode(FavouriteMetadata.self, forKey: Self.metadataKey) ?? FavouriteMetadata()
            if let discourse {
                metadata.discourses[discourse.id] = discourse
                if fresh {
                    metadata.refreshed[Target.discourse(discourse.id).storageKey] = dateProvider()
                    metadata.unavailable.remove(Target.discourse(discourse.id).storageKey)
                }
            }
            if let audio {
                metadata.audios[audio.id] = audio
                if fresh {
                    metadata.refreshed[Target.audio(audio.id).storageKey] = dateProvider()
                    metadata.unavailable.remove(Target.audio(audio.id).storageKey)
                }
            }
            settings.encode(metadata, forKey: Self.metadataKey)
        }
    }

    /// Recover saved payloads before making any requests. Failed requests leave them intact.
    func refreshFavourites() async throws {
        for discourse in DiscourseHistoryStore(settings: settings).recentlyPlayedDiscourses where isLiked(.discourse(discourse.id)) && favouriteMetadata.discourses[discourse.id] == nil {
            capture(discourse: discourse, fresh: false)
        }
        for audio in DiscourseHistoryStore(settings: settings).recentlyPlayedAudios where isLiked(.audio(audio.id)) && favouriteMetadata.audios[audio.id] == nil {
            capture(audio: audio, fresh: false)
        }
        let known = favouriteMetadata
        let needsRecovery = state.discourseIDs.contains { known.discourses[$0] == nil }
            || state.audioIDs.contains { known.audios[$0] == nil }
        let cached = needsRecovery ? DiscourseAPICache.shared.savedFavouritePayloads() : (discourses: [:], audios: [:])
        for id in state.discourseIDs where known.discourses[id] == nil {
            if let value = DiscourseTrackRegistry.shared.discourse(id: id) ?? cached.discourses[id] { capture(discourse: value, fresh: false) }
        }
        for id in state.audioIDs where known.audios[id] == nil {
            if let value = DiscourseTrackRegistry.shared.track(id: id) ?? cached.audios[id] { capture(audio: value, fresh: false) }
        }
        postChange()
        try await refresh()
        let snapshot = state
        let metadata = favouriteMetadata
        let targets = snapshot.discourseIDs.sorted().map { Target.discourse($0) }
            + snapshot.audioIDs.sorted().map { Target.audio($0) }
        let stale = targets.filter {
            guard let date = metadata.refreshed[$0.storageKey] else { return true }
            return dateProvider().timeIntervalSince(date) >= 86400
        }
        for offset in stride(from: 0, to: stale.count, by: 100) {
            let batch = Array(stale[offset..<min(offset + 100, stale.count)])
            let response = try await resolver(
                batch.filter { !$0.isAudio }.map { $0.id },
                batch.filter { $0.isAudio }.map { $0.id })
            queue.sync {
                var saved = settings.decode(FavouriteMetadata.self, forKey: Self.metadataKey) ?? FavouriteMetadata()
                for discourse in response.discourses { saved.discourses[discourse.id] = discourse }
                for audio in response.audios { saved.audios[audio.id] = audio }
                let missing = Set(response.missing_discourse_ids.map { Target.discourse($0).storageKey }
                    + response.missing_discourse_audio_ids.map { Target.audio($0).storageKey })
                for target in batch {
                    saved.refreshed[target.storageKey] = dateProvider()
                    if missing.contains(target.storageKey) { saved.unavailable.insert(target.storageKey) }
                    else { saved.unavailable.remove(target.storageKey) }
                }
                settings.encode(saved, forKey: Self.metadataKey)
            }
            postChange()
        }
    }

    // MARK: - Reading

    var state: State {
        queue.sync { stateStore }
    }

    func isLiked(_ target: Target) -> Bool {
        state.isLiked(target)
    }

    func isPending(_ target: Target) -> Bool {
        state.isPending(target)
    }

    func count(for target: Target) -> Int? {
        state.count(for: target)
    }

    var lastFetchedAt: Date? {
        guard let timestamp = settings.double(Keys.fetchedAt), timestamp > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    var hasCachedState: Bool {
        settings.contains(Keys.discourses)
            && settings.contains(Keys.audios)
            && settings.contains(Keys.fetchedAt)
    }

    // MARK: - Refresh

    /// Refreshes the liked sets when the seven-day window has elapsed (or when
    /// `force` is set). A no-op refresh still returns the current state.
    @discardableResult
    func refresh(force: Bool = false) async throws -> State {
        if !force, hasCachedState, let lastFetchedAt {
            let age = dateProvider().timeIntervalSince(lastFetchedAt)
            if age >= 0, age < Self.refreshInterval {
                return state
            }
        }

        let revision = queue.sync { self.revision }
        let likes = try await service.fetchLikes()
        apply(likes, revision: revision)
        return state
    }

    private func apply(_ likes: DiscourseLikes, revision: Int) {
        queue.sync {
            guard self.revision == revision else { return }
            var state = stateStore
            state.discourseIDs = likes.discourseIDs
            state.audioIDs = likes.audioIDs
            state.pending = state.pending.filter { inFlight.contains($0.key) }
            for (target, liked) in state.pending {
                if liked { state.insert(target) } else { state.remove(target) }
            }
            stateStore = state
            persist(state)
            settings.set(dateProvider().timeIntervalSince1970, forKey: Keys.fetchedAt)
        }
        postChange()
    }

    // MARK: - Toggling

    /// Likes or unlikes a discourse. Returns `nil` when the target is already in
    /// the requested state or a toggle for it is still in flight.
    @discardableResult
    func setDiscourseLiked(_ liked: Bool,
                           id: String,
                           totalLikes: Int) async throws -> Change? {
        try await setLiked(liked, target: .discourse(id), totalLikes: totalLikes)
    }

    /// Likes or unlikes a track. Counts are independent from discourse counts.
    @discardableResult
    func setAudioLiked(_ liked: Bool,
                       id: String,
                       totalLikes: Int) async throws -> Change? {
        try await setLiked(liked, target: .audio(id), totalLikes: totalLikes)
    }

    /// Flips the current state of a discourse.
    @discardableResult
    func toggleDiscourse(id: String, totalLikes: Int) async throws -> Change? {
        try await setDiscourseLiked(!isLiked(.discourse(id)), id: id, totalLikes: totalLikes)
    }

    /// Flips the current state of a track.
    @discardableResult
    func toggleAudio(id: String, totalLikes: Int) async throws -> Change? {
        try await setAudioLiked(!isLiked(.audio(id)), id: id, totalLikes: totalLikes)
    }

    private func setLiked(_ liked: Bool,
                          target: Target,
                          totalLikes: Int) async throws -> Change? {
        let previous: (isLiked: Bool, count: Int?)? = queue.sync {
            let state = stateStore
            guard !state.isPending(target), state.isLiked(target) != liked else {
                return nil
            }

            revision += 1
            inFlight.insert(target)
            let previous = (state.isLiked(target), state.count(for: target))
            var optimistic = state
            optimistic.pending[target] = liked
            if liked {
                var metadata = settings.decode(FavouriteMetadata.self, forKey: Self.metadataKey) ?? FavouriteMetadata()
                metadata.added[target.storageKey] = dateProvider()
                settings.encode(metadata, forKey: Self.metadataKey)
                optimistic.insert(target)
            } else {
                optimistic.remove(target)
            }
            let base = state.count(for: target) ?? totalLikes
            optimistic.counts[target] = max(0, base + (liked ? 1 : -1))
            stateStore = optimistic
            persist(optimistic)
            return previous
        }

        guard let previous else {
            return nil
        }
        postChange()

        do {
            let serverTotal = try await send(liked, target: target)
            let settledTotal = queue.sync { () -> Int in
                var state = stateStore
                let optimisticTotal = state.count(for: target) ?? max(0, serverTotal)
                // A successful response must not reverse the count change shown for this tap.
                let total = liked ? max(optimisticTotal, serverTotal) : min(optimisticTotal, max(0, serverTotal))
                state.counts[target] = total
                confirmedCounts.insert(target)
                revision += 1
                inFlight.remove(target)
                state.pending.removeValue(forKey: target)
                stateStore = state
                persist(state)
                return total
            }
            postChange()
            return Change(target: target, isLiked: liked, totalLikes: settledTotal)
        } catch {
            queue.sync {
                var state = stateStore
                revision += 1
                inFlight.remove(target)
                state.pending.removeValue(forKey: target)
                if previous.isLiked {
                    state.insert(target)
                } else {
                    state.remove(target)
                }
                if let count = previous.count {
                    state.counts[target] = count
                } else {
                    state.counts.removeValue(forKey: target)
                }
                stateStore = state
                persist(state)
            }
            postChange()
            throw error
        }
    }

    private func send(_ liked: Bool, target: Target) async throws -> Int {
        if target.isAudio {
            if liked {
                return try await service.sendAudioLike(id: target.id).totalLikes
            }
            return try await service.sendAudioUnlike(id: target.id).totalLikes
        }
        if liked {
            return try await service.sendDiscourseLike(id: target.id).totalLikes
        }
        return try await service.sendDiscourseUnlike(id: target.id).totalLikes
    }

    // MARK: - Counts from list payloads

    /// Records a count that arrived with a catalogue payload. Pending toggles
    /// and confirmed mutations win over potentially stale cached list counts for this session.
    func updateCount(_ totalLikes: Int, for target: Target) {
        queue.sync {
            guard !stateStore.isPending(target), !confirmedCounts.contains(target) else {
                return
            }
            var state = stateStore
            state.counts[target] = max(0, totalLikes)
            stateStore = state
        }
    }

    /// Drops everything. Used by a future "reset my data" action and by tests.
    func reset() {
        queue.sync {
            stateStore = State()
            confirmedCounts.removeAll()
            settings.remove(Keys.discourses)
            settings.remove(Keys.audios)
            settings.remove(Keys.fetchedAt)
            settings.remove(Keys.pending)
            settings.remove(Self.metadataKey)
        }
        postChange()
    }

    // MARK: - Persistence

    private func persist(_ state: State) {
        var metadata = settings.decode(FavouriteMetadata.self, forKey: Self.metadataKey) ?? FavouriteMetadata()
        for collection in Collection.allCases {
            let ids = collection == .tracks ? state.audioIDs : state.discourseIDs
            if !ids.isEmpty { metadata.created.insert(collection.rawValue) }
            for id in ids.sorted() {
                let target = Target(id: id, isAudio: collection == .tracks)
                if metadata.added[target.storageKey] == nil {
                    metadata.added[target.storageKey] = state.pending[target] == true ? dateProvider() : .distantPast
                }
            }
        }
        settings.encode(metadata, forKey: Self.metadataKey)
        settings.set(state.discourseIDs, forKey: Keys.discourses)
        settings.set(state.audioIDs, forKey: Keys.audios)
        var pending: [String: Bool] = [:]
        for (target, liked) in state.pending {
            pending[target.storageKey] = liked
        }
        if pending.isEmpty {
            settings.remove(Keys.pending)
        } else {
            settings.encode(pending, forKey: Keys.pending)
        }
    }

    private func postChange() {
        post(.discourseLikesDidChange)
    }

    private func post(_ name: Notification.Name) {
        let notificationCenter = self.notificationCenter
        if Thread.isMainThread {
            notificationCenter.post(name: name, object: self)
        } else {
            DispatchQueue.main.async {
                notificationCenter.post(name: name, object: self)
            }
        }
    }
}
