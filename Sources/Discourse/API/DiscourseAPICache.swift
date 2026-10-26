/*****************************************************************************
 * DiscourseAPICache.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * A small on-disk cache for successful GET payloads. The backend does not send
 * cache headers, so `URLCache` cannot be used for the 24 hour policy: this store
 * keeps the raw JSON body per request URL and remembers when it was written.
 *
 * Policy (see AGENTS.md section 6.2):
 *   - entries are fresh for 24 hours;
 *   - the total size is capped at ~10 MB, oldest entries are evicted first;
 *   - stale entries stay readable so a failed refresh never blanks the UI;
 *   - `/likes` is never cached, enforced by the client, not here.
 *****************************************************************************/

import CryptoKit
import Foundation

final class DiscourseAPICache {
    /// Freshness window for a cached GET response.
    static let timeToLive: TimeInterval = 24 * 60 * 60
    /// Soft cap for the on-disk payloads.
    static let capacity: Int = 10 * 1024 * 1024

    static let shared = DiscourseAPICache()

    private let directory: URL
    private let queue = DispatchQueue(label: "online.sandalbar.rajneesh-discourse.api-cache")
    private let fileManager = FileManager.default
    private let dateProvider: () -> Date

    init(directory: URL? = nil, dateProvider: @escaping () -> Date = Date.init) {
        let base = directory ?? Self.defaultDirectory()
        self.directory = base
        self.dateProvider = dateProvider

        do {
            try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableBase = base
            try? mutableBase.setResourceValues(values)
        } catch {
            DiscourseDiagnostics.log("cache directory unavailable: \(error.localizedDescription)", context: "cache")
        }
    }

    private static func defaultDirectory() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return caches.appendingPathComponent("DiscourseAPI", isDirectory: true)
    }

    // MARK: - Reading

    /// Returns the cached body for `url` together with its freshness.
    func cachedData(for url: URL) -> (data: Data, isFresh: Bool)? {
        queue.sync {
            let fileURL = self.fileURL(for: url)
            guard let data = try? Data(contentsOf: fileURL),
                  let storedAt = self.modificationDate(of: fileURL) else {
                return nil
            }
            let age = dateProvider().timeIntervalSince(storedAt)
            return (data, age < Self.timeToLive)
        }
    }

    /// Fresh cached body, if any.
    func freshData(for url: URL) -> Data? {
        guard let entry = cachedData(for: url), entry.isFresh else {
            return nil
        }
        return entry.data
    }

    /// Cached body regardless of age, for stale-on-failure fallbacks.
    func staleData(for url: URL) -> Data? {
        cachedData(for: url)?.data
    }

    // MARK: - Writing

    func store(_ data: Data, for url: URL) {
        queue.sync {
            let fileURL = self.fileURL(for: url)
            do {
                try data.write(to: fileURL, options: .atomic)
                try fileManager.setAttributes([.modificationDate: dateProvider()], ofItemAtPath: fileURL.path)
                self.trimToCapacity(excluding: fileURL)
            } catch {
                DiscourseDiagnostics.log("could not cache \(url.path): \(error.localizedDescription)",
                                         level: .warning,
                                         context: "cache")
            }
        }
    }

    func removeAll() {
        queue.sync {
            guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
                return
            }
            for name in names {
                try? fileManager.removeItem(at: directory.appendingPathComponent(name))
            }
        }
    }

    // MARK: - Internals

    private func fileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name).appendingPathExtension("json")
    }

    private func modificationDate(of url: URL) -> Date? {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date
    }

    /// Evicts the oldest entries until the cache fits its budget again.
    private func trimToCapacity(excluding newest: URL) {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            return
        }
        var entries: [(url: URL, size: Int, modified: Date)] = []
        for name in names {
            let url = directory.appendingPathComponent(name)
            guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                  let size = (attributes[.size] as? NSNumber)?.intValue,
                  let modified = attributes[.modificationDate] as? Date else {
                continue
            }
            entries.append((url, size, modified))
        }

        var total = entries.reduce(0) { $0 + $1.size }
        guard total > Self.capacity else {
            return
        }

        for entry in entries.sorted(by: { $0.modified < $1.modified }) where entry.url != newest {
            try? fileManager.removeItem(at: entry.url)
            total -= entry.size
            if total <= Self.capacity {
                break
            }
        }
    }
}
