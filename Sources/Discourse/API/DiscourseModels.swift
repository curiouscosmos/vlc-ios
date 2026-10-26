/*****************************************************************************
 * DiscourseModels.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * The payloads mirror `api/types/discourse.type.ts`. Decoding is deliberately
 * defensive: a missing or unexpected field never crashes the app, it falls back
 * to an empty/default value.
 *****************************************************************************/

import Foundation

// MARK: - Catalogue

/// A discourse in the remote catalogue.
struct Discourse: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let thumbnailURLString: String?
    let isAudioCleaned: Bool
    let language: String
    let slug: String?
    let totalTracks: Int
    let totalLikes: Int
    let createdAt: String
    let updatedAt: String
    /// Only present on `/stats` payloads.
    let plays: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case thumbnailURLString = "thumbnail_url"
        case isAudioCleaned = "is_audio_cleaned"
        case language
        case slug
        case totalTracks = "total_tracks"
        case totalLikes = "total_likes"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case plays
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        thumbnailURLString = try container.decodeIfPresent(String.self, forKey: .thumbnailURLString)
        isAudioCleaned = try container.decodeIfPresent(Bool.self, forKey: .isAudioCleaned) ?? false
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? ""
        slug = try container.decodeIfPresent(String.self, forKey: .slug)
        totalTracks = try container.decodeIfPresent(Int.self, forKey: .totalTracks) ?? 0
        totalLikes = try container.decodeIfPresent(Int.self, forKey: .totalLikes) ?? 0
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        plays = try container.decodeIfPresent(Int.self, forKey: .plays)
    }

    /// Memberwise initialiser kept for tests, caches and optimistic updates.
    init(id: String,
         title: String,
         thumbnailURLString: String? = nil,
         isAudioCleaned: Bool = false,
         language: String = "",
         slug: String? = nil,
         totalTracks: Int = 0,
         totalLikes: Int = 0,
         createdAt: String = "",
         updatedAt: String = "",
         plays: Int? = nil) {
        self.id = id
        self.title = title
        self.thumbnailURLString = thumbnailURLString
        self.isAudioCleaned = isAudioCleaned
        self.language = language
        self.slug = slug
        self.totalTracks = totalTracks
        self.totalLikes = totalLikes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.plays = plays
    }

    var thumbnailURL: URL? {
        DiscourseURLResolver.resolve(thumbnailURLString)
    }

    var playCount: Int {
        plays ?? 0
    }
}

/// A single track (audio) of a discourse.
struct DiscourseAudio: Codable, Hashable, Identifiable {
    let id: String
    let discourseID: String
    let discourseName: String
    let discourseThumbnailURLString: String?
    let language: String
    let title: String
    let audioURLString: String
    let durationSeconds: Double?
    let fileSize: Int64?
    let mimeType: String?
    let trackNumber: Int?
    let totalLikes: Int
    let createdAt: String
    let updatedAt: String
    /// Only present on `/stats` payloads.
    let plays: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case discourseID = "discourse_id"
        case discourseName = "discourse_name"
        case discourseThumbnailURLString = "discourse_thumbnail_url"
        case language
        case title
        case audioURLString = "audio_url"
        case durationSeconds = "duration_seconds"
        case fileSize = "file_size"
        case mimeType = "mime_type"
        case trackNumber = "track_number"
        case totalLikes = "total_likes"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case plays
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        discourseID = try container.decodeIfPresent(String.self, forKey: .discourseID) ?? ""
        discourseName = try container.decodeIfPresent(String.self, forKey: .discourseName) ?? ""
        discourseThumbnailURLString = try container.decodeIfPresent(String.self, forKey: .discourseThumbnailURLString)
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        audioURLString = try container.decodeIfPresent(String.self, forKey: .audioURLString) ?? ""
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds)
        fileSize = try container.decodeIfPresent(Int64.self, forKey: .fileSize)
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        trackNumber = try container.decodeIfPresent(Int.self, forKey: .trackNumber)
        totalLikes = try container.decodeIfPresent(Int.self, forKey: .totalLikes) ?? 0
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        plays = try container.decodeIfPresent(Int.self, forKey: .plays)
    }

    /// Memberwise initialiser kept for tests, caches and optimistic updates.
    init(id: String,
         discourseID: String,
         discourseName: String,
         discourseThumbnailURLString: String? = nil,
         language: String = "",
         title: String,
         audioURLString: String,
         durationSeconds: Double? = nil,
         fileSize: Int64? = nil,
         mimeType: String? = nil,
         trackNumber: Int? = nil,
         totalLikes: Int = 0,
         createdAt: String = "",
         updatedAt: String = "",
         plays: Int? = nil) {
        self.id = id
        self.discourseID = discourseID
        self.discourseName = discourseName
        self.discourseThumbnailURLString = discourseThumbnailURLString
        self.language = language
        self.title = title
        self.audioURLString = audioURLString
        self.durationSeconds = durationSeconds
        self.fileSize = fileSize
        self.mimeType = mimeType
        self.trackNumber = trackNumber
        self.totalLikes = totalLikes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.plays = plays
    }

    var audioURL: URL? {
        DiscourseURLResolver.resolve(audioURLString)
    }

    var thumbnailURL: URL? {
        DiscourseURLResolver.resolve(discourseThumbnailURLString)
    }

    /// Artwork shown for a track: the discourse artwork.
    var artworkURL: URL? {
        thumbnailURL
    }

    var playCount: Int {
        plays ?? 0
    }

    /// Duration in milliseconds, as `VLCMedia` expects it.
    var durationMilliseconds: Int64? {
        guard let durationSeconds, durationSeconds > 0 else {
            return nil
        }
        return Int64((durationSeconds * 1000).rounded())
    }
}

// MARK: - Pagination

struct DiscoursePaginationMeta: Codable, Hashable {
    let page: Int
    let pageSize: Int
    let totalRecords: Int
    let totalPages: Int

    enum CodingKeys: String, CodingKey {
        case page
        case pageSize = "page_size"
        case totalRecords = "total_records"
        case totalPages = "total_pages"
    }

    init(page: Int = 1, pageSize: Int = 16, totalRecords: Int = 0, totalPages: Int = 1) {
        self.page = page
        self.pageSize = pageSize
        self.totalRecords = totalRecords
        self.totalPages = totalPages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        page = try container.decodeIfPresent(Int.self, forKey: .page) ?? 1
        pageSize = try container.decodeIfPresent(Int.self, forKey: .pageSize) ?? 16
        totalRecords = try container.decodeIfPresent(Int.self, forKey: .totalRecords) ?? 0
        totalPages = try container.decodeIfPresent(Int.self, forKey: .totalPages) ?? 1
    }
}

/// A paginated payload. `Item` is `Discourse` or `DiscourseAudio`.
struct DiscoursePage<Item: Decodable>: Decodable {
    let data: [Item]
    let meta: DiscoursePaginationMeta

    init(data: [Item], meta: DiscoursePaginationMeta = DiscoursePaginationMeta()) {
        self.data = data
        self.meta = meta
    }

    enum CodingKeys: String, CodingKey {
        case data
        case meta
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decodeIfPresent([Item].self, forKey: .data) ?? []
        meta = try container.decodeIfPresent(DiscoursePaginationMeta.self, forKey: .meta) ?? DiscoursePaginationMeta()
    }
}

struct DiscourseTotalRecordsMeta: Decodable, Hashable {
    let totalRecords: Int

    enum CodingKeys: String, CodingKey {
        case totalRecords = "total_records"
    }

    init(totalRecords: Int = 0) {
        self.totalRecords = totalRecords
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalRecords = try container.decodeIfPresent(Int.self, forKey: .totalRecords) ?? 0
    }
}

/// Response of `GET /discourse-audios?discourse_id=…` (no pagination).
struct DiscourseAudiosEnvelope: Decodable {
    let data: [DiscourseAudio]
    let meta: DiscourseTotalRecordsMeta

    init(data: [DiscourseAudio], meta: DiscourseTotalRecordsMeta = DiscourseTotalRecordsMeta()) {
        self.data = data
        self.meta = meta
    }

    enum CodingKeys: String, CodingKey {
        case data
        case meta
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decodeIfPresent([DiscourseAudio].self, forKey: .data) ?? []
        meta = try container.decodeIfPresent(DiscourseTotalRecordsMeta.self, forKey: .meta) ?? DiscourseTotalRecordsMeta()
    }
}

// MARK: - Likes

struct DiscourseLikes: Decodable, Hashable {
    let discourseIDs: Set<String>
    let audioIDs: Set<String>

    enum CodingKeys: String, CodingKey {
        case discourseIDs = "discourse"
        case audioIDs = "discourse_audio"
    }

    init(discourseIDs: Set<String> = [], audioIDs: Set<String> = []) {
        self.discourseIDs = discourseIDs
        self.audioIDs = audioIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        discourseIDs = Set(try container.decodeIfPresent([String].self, forKey: .discourseIDs) ?? [])
        audioIDs = Set(try container.decodeIfPresent([String].self, forKey: .audioIDs) ?? [])
    }
}

struct DiscourseLikeRequest: Encodable {
    let userID: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
    }
}

/// Result of `DELETE /likes`.
struct DiscourseUnlikeResult: Decodable, Hashable {
    let discourseID: String?
    let audioID: String?
    let likedByUserID: String?
    let unliked: Bool
    let totalLikes: Int

    enum CodingKeys: String, CodingKey {
        case discourseID = "discourse_id"
        case audioID = "discourse_audio_id"
        case likedByUserID = "liked_by_user_id"
        case unliked
        case totalLikes = "total_likes"
    }

    init(discourseID: String? = nil,
         audioID: String? = nil,
         likedByUserID: String? = nil,
         unliked: Bool = false,
         totalLikes: Int = 0) {
        self.discourseID = discourseID
        self.audioID = audioID
        self.likedByUserID = likedByUserID
        self.unliked = unliked
        self.totalLikes = totalLikes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        discourseID = try container.decodeIfPresent(String.self, forKey: .discourseID)
        audioID = try container.decodeIfPresent(String.self, forKey: .audioID)
        likedByUserID = try container.decodeIfPresent(String.self, forKey: .likedByUserID)
        unliked = try container.decodeIfPresent(Bool.self, forKey: .unliked) ?? false
        totalLikes = try container.decodeIfPresent(Int.self, forKey: .totalLikes) ?? 0
    }
}

/// Result of `PUT /discourses/:id/like` and `PUT /discourse-audios/:id/like`.
struct DiscourseLikeResult: Decodable, Hashable {
    let discourseID: String?
    let audioID: String?
    let likedByUserID: String?
    let liked: Bool
    let totalLikes: Int

    enum CodingKeys: String, CodingKey {
        case discourseID = "discourse_id"
        case audioID = "discourse_audio_id"
        case likedByUserID = "liked_by_user_id"
        case liked
        case totalLikes = "total_likes"
    }

    init(discourseID: String? = nil,
         audioID: String? = nil,
         likedByUserID: String? = nil,
         liked: Bool = false,
         totalLikes: Int = 0) {
        self.discourseID = discourseID
        self.audioID = audioID
        self.likedByUserID = likedByUserID
        self.liked = liked
        self.totalLikes = totalLikes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        discourseID = try container.decodeIfPresent(String.self, forKey: .discourseID)
        audioID = try container.decodeIfPresent(String.self, forKey: .audioID)
        likedByUserID = try container.decodeIfPresent(String.self, forKey: .likedByUserID)
        liked = try container.decodeIfPresent(Bool.self, forKey: .liked) ?? false
        totalLikes = try container.decodeIfPresent(Int.self, forKey: .totalLikes) ?? 0
    }
}

struct DiscourseLikeEnvelope: Decodable {
    let data: DiscourseLikeResult

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode(DiscourseLikeResult.self, forKey: .data)
    }

    enum CodingKeys: String, CodingKey {
        case data
    }
}

struct DiscourseUnlikeEnvelope: Decodable {
    let data: DiscourseUnlikeResult

    enum CodingKeys: String, CodingKey {
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode(DiscourseUnlikeResult.self, forKey: .data)
    }
}

// MARK: - Listening stats

struct DiscourseStatsRequest: Encodable {
    let userID: String
    let discourseID: String
    let audioID: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case discourseID = "discourse_id"
        case audioID = "discourse_audio_id"
    }
}

struct DiscourseStatsResult: Decodable, Hashable {
    let recorded: Bool
    let reason: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recorded = try container.decodeIfPresent(Bool.self, forKey: .recorded) ?? false
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
    }

    enum CodingKeys: String, CodingKey {
        case recorded
        case reason
    }
}

struct DiscourseStatsEnvelope: Decodable {
    let data: DiscourseStatsResult

    enum CodingKeys: String, CodingKey {
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode(DiscourseStatsResult.self, forKey: .data)
    }
}

/// Response of `GET /stats` for either dimension; the payload is a plain list.
struct DiscourseStatsListEnvelope<Item: Decodable>: Decodable {
    let data: [Item]

    enum CodingKeys: String, CodingKey {
        case data
    }

    init(data: [Item] = []) {
        self.data = data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decodeIfPresent([Item].self, forKey: .data) ?? []
    }
}

// MARK: - Query values

enum DiscourseLanguage: String, Codable, CaseIterable, Hashable {
    case hindi
    case english

    var displayName: String {
        switch self {
        case .hindi:
            return NSLocalizedString("DISCOURSE_LANGUAGE_HINDI", comment: "Hindi language filter")
        case .english:
            return NSLocalizedString("DISCOURSE_LANGUAGE_ENGLISH", comment: "English language filter")
        }
    }
}

enum DiscourseCatalogueSort: String, Codable, Hashable {
    case mostLiked = "most_liked"
}

enum DiscourseStatsDimension: String, Hashable {
    case discourse
    case audio = "discourse_audio"
}

enum DiscourseStatsWindow: String, Hashable {
    case last7Days = "7_days"
    case last24Hours = "24_hours"
}

// MARK: - Error copy

enum DiscourseErrorCopy {
    static var serverFailure: String {
        NSLocalizedString("DISCOURSE_SERVER_ERROR",
                          comment: "Generic error shown when the discourse server cannot be reached")
    }

    static var likeFailure: String {
        NSLocalizedString("DISCOURSE_LIKE_ERROR",
                          comment: "Error shown when a like or unlike request fails")
    }
}
