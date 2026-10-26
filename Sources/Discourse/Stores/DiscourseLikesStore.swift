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
 *   - success adopts the server's `total_likes` and keeps the new membership;
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
    private let dateProvider: () -> Date
    private let notificationCenter: NotificationCenter
    private let queue = DispatchQueue(label: "online.sandalbar.rajneesh-discourse.likes")
    private var stateStore: State

    init(settings: DiscourseSettings = .shared,
         service: DiscourseLikeService = DiscourseAPIClient.shared,
         dateProvider: @escaping () -> Date = Date.init,
         notificationCenter: NotificationCenter = .default) {
        self.settings = settings
        self.service = service
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

        let likes = try await service.fetchLikes()
        apply(likes)
        return state
    }

    private func apply(_ likes: DiscourseLikes) {
        queue.sync {
            var state = stateStore
            state.discourseIDs = likes.discourseIDs
            state.audioIDs = likes.audioIDs
            // The server answered for this install: whatever was pending is settled.
            state.pending.removeAll()
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

            let previous = (state.isLiked(target), state.count(for: target))
            var optimistic = state
            optimistic.pending[target] = liked
            if liked {
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
            queue.sync {
                var state = stateStore
                state.counts[target] = max(0, serverTotal)
                state.pending.removeValue(forKey: target)
                stateStore = state
                persist(state)
            }
            postChange()
            return Change(target: target, isLiked: liked, totalLikes: max(0, serverTotal))
        } catch {
            queue.sync {
                var state = stateStore
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
    /// keep their optimistic count so a list refresh cannot undo a tap.
    func updateCount(_ totalLikes: Int, for target: Target) {
        queue.sync {
            guard stateStore.isPending(target) == false else {
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
            settings.remove(Keys.discourses)
            settings.remove(Keys.audios)
            settings.remove(Keys.fetchedAt)
            settings.remove(Keys.pending)
        }
        postChange()
    }

    // MARK: - Persistence

    private func persist(_ state: State) {
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
