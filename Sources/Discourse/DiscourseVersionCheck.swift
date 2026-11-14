/*****************************************************************************
 * DiscourseVersionCheck.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 *****************************************************************************/

import Foundation

struct DiscourseVersionPolicy: Decodable {
    let minSupportedVersion: String
    let forceUpdate: Bool

    // unstableVersions is intentionally ignored: only versions below the minimum prompt.
    func requiresUpdate(currentVersion: String) -> Bool {
        guard let current = Self.components(currentVersion),
              let minimum = Self.components(minSupportedVersion) else { return false }
        for index in 0..<max(current.count, minimum.count) {
            let lhs = index < current.count ? current[index] : 0
            let rhs = index < minimum.count ? minimum[index] : 0
            if lhs != rhs { return lhs < rhs }
        }
        return false
    }

    private static func components(_ version: String) -> [UInt64]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var result: [UInt64] = []
        for part in parts {
            guard !part.isEmpty, part.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
                  let value = UInt64(part) else { return nil }
            result.append(value)
        }
        return result
    }
}

struct DiscourseVersionCheck: Decodable {
    let ios: DiscourseVersionPolicy

    static var request: URLRequest? {
        guard let url = URL(string: "https://osho.b-cdn.net/app/version_check.json") else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        return request
    }

    static func fetch(session: URLSession = .shared) async throws -> DiscourseVersionPolicy? {
        guard let request = request else { return nil }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { return nil }
        return try JSONDecoder().decode(Self.self, from: data).ios
    }
}
