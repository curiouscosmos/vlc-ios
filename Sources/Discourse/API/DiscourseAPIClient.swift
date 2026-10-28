/*****************************************************************************
 * DiscourseAPIClient.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * One place that knows how to talk to the discourse backend:
 *   - `x-api-key` on every request, injected at build time (AGENTS.md 3.4);
 *   - successful GETs cached for 24 hours, `/likes` excluded;
 *   - transport failures and 5xx answers fall back to stale cache;
 *   - force refresh sends `Cache-Control: no-cache`;
 *   - every failure is mapped to `DiscourseAPIError`.
 *
 * The client knows nothing about UI state. Callers keep their rendered content
 * when a request fails; the client never deletes cached payloads on error.
 *****************************************************************************/

import Foundation

final class DiscourseAPIClient {
    static let shared = DiscourseAPIClient()

    /// Path segment that must never be served from, or written to, the cache.
    private static let uncacheablePath = "likes"

    private let apiKey: String
    private let baseURL: URL?
    private let session: URLSession
    private let cache: DiscourseAPICache
    private let identity: DiscourseIdentity

    init(apiKey: String = RD_API_KEY,
         baseURLString: String = RD_API_BASE_URL,
         cache: DiscourseAPICache = .shared,
         identity: DiscourseIdentity = .shared,
         sessionConfiguration: URLSessionConfiguration? = nil) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseURL = Self.parseBaseURL(baseURLString)
        self.cache = cache
        self.identity = identity
        self.session = URLSession(configuration: sessionConfiguration ?? Self.defaultConfiguration)
    }

    // MARK: - Catalogue

    func discourses(page: Int = 1,
                    search: String? = nil,
                    isAudioCleaned: Bool? = nil,
                    language: DiscourseLanguage? = nil,
                    sort: DiscourseCatalogueSort? = nil,
                    forceRefresh: Bool = false) async throws -> DiscoursePage<Discourse> {
        return try await get("discourses",
                             query: Self.discourseQuery(page: page,
                                                        search: search,
                                                        isAudioCleaned: isAudioCleaned,
                                                        language: language,
                                                        sort: sort),
                             cacheable: true,
                             forceRefresh: forceRefresh)
    }

    /// The last cached catalogue page, fresh or stale, for an immediate render
    /// before the network revalidates it.
    func cachedDiscourses(page: Int = 1,
                          search: String? = nil,
                          isAudioCleaned: Bool? = nil,
                          language: DiscourseLanguage? = nil,
                          sort: DiscourseCatalogueSort? = nil) -> DiscoursePage<Discourse>? {
        return cached(path: "discourses",
                      query: Self.discourseQuery(page: page,
                                                 search: search,
                                                 isAudioCleaned: isAudioCleaned,
                                                 language: language,
                                                 sort: sort))
    }

    private static func discourseQuery(page: Int,
                                       search: String?,
                                       isAudioCleaned: Bool?,
                                       language: DiscourseLanguage?,
                                       sort: DiscourseCatalogueSort?) -> [String: String] {
        var query: [String: String] = ["page": String(max(1, page))]
        if let search = clean(search) {
            query["search"] = search
        }
        if let isAudioCleaned {
            query["is_audio_cleaned"] = isAudioCleaned ? "true" : "false"
        }
        if let language {
            query["language"] = language.rawValue
        }
        if let sort {
            query["sort"] = sort.rawValue
        }
        return query
    }

    func discourseAudios(page: Int = 1,
                         search: String? = nil,
                         discourseName: String? = nil,
                         language: DiscourseLanguage? = nil,
                         sort: DiscourseCatalogueSort? = nil,
                         forceRefresh: Bool = false) async throws -> DiscoursePage<DiscourseAudio> {
        return try await get("discourse-audios",
                             query: Self.discourseAudiosQuery(page: page,
                                                              search: search,
                                                              discourseName: discourseName,
                                                              language: language,
                                                              sort: sort),
                             cacheable: true,
                             forceRefresh: forceRefresh)
    }

    /// The last cached track page, fresh or stale, for an immediate render before
    /// the network revalidates it.
    func cachedDiscourseAudios(page: Int = 1,
                               search: String? = nil,
                               discourseName: String? = nil,
                               language: DiscourseLanguage? = nil,
                               sort: DiscourseCatalogueSort? = nil) -> DiscoursePage<DiscourseAudio>? {
        return cached(path: "discourse-audios",
                      query: Self.discourseAudiosQuery(page: page,
                                                       search: search,
                                                       discourseName: discourseName,
                                                       language: language,
                                                       sort: sort))
    }

    private static func discourseAudiosQuery(page: Int,
                                             search: String?,
                                             discourseName: String?,
                                             language: DiscourseLanguage?,
                                             sort: DiscourseCatalogueSort?) -> [String: String] {
        var query: [String: String] = ["page": String(max(1, page))]
        if let search = clean(search) {
            query["search"] = search
        }
        if let discourseName = clean(discourseName) {
            query["discourse_name"] = discourseName
        }
        if let language {
            query["language"] = language.rawValue
        }
        if let sort {
            query["sort"] = sort.rawValue
        }
        return query
    }

    /// All tracks of one discourse (this route is not paginated).
    func discourseTracks(discourseID: String, forceRefresh: Bool = false) async throws -> [DiscourseAudio] {
        let envelope: DiscourseAudiosEnvelope = try await get("discourse-audios",
                                                              query: ["discourse_id": discourseID],
                                                              cacheable: true,
                                                              forceRefresh: forceRefresh)
        return envelope.data
    }

    /// The last cached track list for one discourse, fresh or stale.
    func cachedDiscourseTracks(discourseID: String) -> [DiscourseAudio]? {
        let envelope: DiscourseAudiosEnvelope? = cached(path: "discourse-audios",
                                                        query: ["discourse_id": discourseID])
        return envelope?.data
    }

    struct FavouriteResolution: Decodable {
        let discourses: [Discourse]
        let audios: [DiscourseAudio]
        let missing_discourse_ids: [String]
        let missing_discourse_audio_ids: [String]
    }

    func resolveFavourites(discourses: [String], audios: [String]) async throws -> FavouriteResolution {
        let body = try JSONSerialization.data(withJSONObject: ["discourse_ids": discourses,
                                                                "discourse_audio_ids": audios])
        return try await get("favourites/resolve", method: "POST", body: body, cacheable: false)
    }

    // MARK: - Likes

    /// Likes of this install. Never cached: the endpoint is user specific.
    func likes(forceRefresh: Bool = false) async throws -> DiscourseLikes {
        try await get("likes",
                      query: ["user_id": identity.userID],
                      cacheable: false,
                      forceRefresh: forceRefresh)
    }

    func likeDiscourse(id: String) async throws -> DiscourseLikeResult {
        let body = try encode(DiscourseLikeRequest(userID: identity.userID))
        let envelope: DiscourseLikeEnvelope = try await get("discourses/\(id)/like",
                                                             method: "PUT",
                                                             body: body,
                                                             cacheable: false)
        return envelope.data
    }

    func likeAudio(id: String) async throws -> DiscourseLikeResult {
        let body = try encode(DiscourseLikeRequest(userID: identity.userID))
        let envelope: DiscourseLikeEnvelope = try await get("discourse-audios/\(id)/like",
                                                             method: "PUT",
                                                             body: body,
                                                             cacheable: false)
        return envelope.data
    }

    func unlikeDiscourse(id: String) async throws -> DiscourseUnlikeResult {
        let envelope: DiscourseUnlikeEnvelope = try await get("likes",
                                                              query: ["user_id": identity.userID,
                                                                      "discourse_id": id],
                                                              method: "DELETE",
                                                              cacheable: false)
        return envelope.data
    }

    func unlikeAudio(id: String) async throws -> DiscourseUnlikeResult {
        let envelope: DiscourseUnlikeEnvelope = try await get("likes",
                                                              query: ["user_id": identity.userID,
                                                                      "discourse_audio_id": id],
                                                              method: "DELETE",
                                                              cacheable: false)
        return envelope.data
    }

    // MARK: - Listening stats

    /// Records a qualified play. Repeats within 24 hours are answered with
    /// `recorded == false`, which is not an error.
    func recordStats(discourseID: String, audioID: String) async throws -> DiscourseStatsResult {
        let body = try encode(DiscourseStatsRequest(userID: identity.userID,
                                                    discourseID: discourseID,
                                                    audioID: audioID))
        let envelope: DiscourseStatsEnvelope = try await get("stats",
                                                             method: "POST",
                                                             body: body,
                                                             cacheable: false)
        return envelope.data
    }

    func discourseStats(dimension: DiscourseStatsDimension = .discourse,
                        window: DiscourseStatsWindow = .last7Days,
                        forceRefresh: Bool = false) async throws -> [Discourse] {
        let envelope: DiscourseStatsListEnvelope<Discourse> = try await get("stats",
                                                                            query: ["by": dimension.rawValue,
                                                                                    "time": window.rawValue],
                                                                            cacheable: true,
                                                                            forceRefresh: forceRefresh)
        return envelope.data
    }

    func audioStats(dimension: DiscourseStatsDimension = .audio,
                    window: DiscourseStatsWindow = .last7Days,
                    forceRefresh: Bool = false) async throws -> [DiscourseAudio] {
        let envelope: DiscourseStatsListEnvelope<DiscourseAudio> = try await get("stats",
                                                                                 query: ["by": dimension.rawValue,
                                                                                         "time": window.rawValue],
                                                                                 cacheable: true,
                                                                                 forceRefresh: forceRefresh)
        return envelope.data
    }

    // MARK: - Request plumbing

    /// Reads any cached body, including stale data, for the SWR first render.
    private func cached<Response: Decodable>(path: String, query: [String: String]) -> Response? {
        guard let url = try? makeURL(path: path, query: query),
              let data = cache.staleData(for: url) else {
            return nil
        }
        return try? decode(data, path: path)
    }

    private func get<Response: Decodable>(_ path: String,
                                          query: [String: String] = [:],
                                          method: String = "GET",
                                          body: Data? = nil,
                                          cacheable: Bool,
                                          forceRefresh: Bool = false) async throws -> Response {
        let url = try makeURL(path: path, query: query)
        // `/likes` is user specific and must never be cached, whatever the caller asked.
        let isCacheable = cacheable && !path.hasPrefix(Self.uncacheablePath)

        if method == "GET", isCacheable, !forceRefresh,
           let cached = cache.freshData(for: url) {
            return try decode(cached, path: path)
        }

        var headers: [String: String] = [:]
        if forceRefresh {
            headers["Cache-Control"] = "no-cache"
        }

        let data = try await fetch(url: url,
                                   method: method,
                                   body: body,
                                   headers: headers,
                                   cacheable: isCacheable)

        let decoded: Response = try decode(data, path: path)
        if method == "GET", isCacheable {
            cache.store(data, for: url)
        }
        return decoded
    }

    private func fetch(url: URL,
                       method: String,
                       body: Data?,
                       headers: [String: String],
                       cacheable: Bool) async throws -> Data {
        guard !apiKey.isEmpty, baseURL != nil else {
            throw DiscourseAPIError.missingConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw DiscourseAPIError.transport(URLError(.badServerResponse))
            }

            if (200..<300).contains(httpResponse.statusCode) {
                return data
            }

            if httpResponse.statusCode >= 500,
               cacheable,
               let stale = cache.staleData(for: url) {
                DiscourseDiagnostics.log("serving cached /\(Self.describe(url)) after HTTP \(httpResponse.statusCode)",
                                         level: .warning,
                                         context: "api")
                return stale
            }

            throw DiscourseAPIError.http(status: httpResponse.statusCode)
        } catch let error as DiscourseAPIError {
            throw error
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw DiscourseAPIError.cancelled
            }
            if cacheable, let stale = cache.staleData(for: url) {
                DiscourseDiagnostics.log("serving cached /\(Self.describe(url)) after a transport failure",
                                         level: .warning,
                                         context: "api")
                return stale
            }
            let mapped = Self.map(error)
            if !mapped.isConnectivityFailure {
                DiscourseDiagnostics.log("request /\(Self.describe(url)) failed: \(mapped.diagnosticDescription)",
                                         context: "api")
            }
            throw mapped
        }
    }

    private func decode<Response: Decodable>(_ data: Data, path: String) throws -> Response {
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            DiscourseDiagnostics.log("could not decode /\(path): \(DiscourseAPIError.decoding(error).diagnosticDescription)",
                                     context: "api")
            throw DiscourseAPIError.decoding(error)
        }
    }

    private func encode<Body: Encodable>(_ body: Body) throws -> Data {
        do {
            return try JSONEncoder().encode(body)
        } catch {
            throw DiscourseAPIError.decoding(error)
        }
    }

    private func makeURL(path: String, query: [String: String]) throws -> URL {
        guard let baseURL else {
            throw DiscourseAPIError.missingConfiguration
        }

        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(url: baseURL.appendingPathComponent(trimmedPath),
                                             resolvingAgainstBaseURL: false) else {
            throw DiscourseAPIError.invalidURL(path: trimmedPath)
        }

        if !query.isEmpty {
            var items = components.queryItems ?? []
            // Stable order keeps cache keys reproducible.
            for key in query.keys.sorted() {
                if let value = query[key] {
                    items.append(URLQueryItem(name: key, value: value))
                }
            }
            components.queryItems = items
        }

        guard let url = components.url else {
            throw DiscourseAPIError.invalidURL(path: trimmedPath)
        }
        return url
    }

    // MARK: - Helpers

    static func clean(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    /// Path without the query string, safe to log (the likes query carries the user UUID).
    private static func describe(_ url: URL) -> String {
        url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func parseBaseURL(_ rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            return nil
        }
        return url
    }

    private static var defaultConfiguration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        // Read budget from the product spec. URLSession has a single idle timeout
        // and no connect-only timeout; see AGENTS.md section 10.11.
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }

    private static func map(_ error: Error) -> DiscourseAPIError {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled:
                return .cancelled
            case .timedOut:
                return .timedOut
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                 .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed,
                 .internationalRoamingOff, .callIsActive:
                return .offline(urlError)
            default:
                return .transport(urlError)
            }
        }
        if error is DecodingError {
            return .decoding(error)
        }
        return .transport(error)
    }
}
