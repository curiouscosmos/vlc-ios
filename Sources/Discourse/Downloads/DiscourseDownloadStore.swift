/*****************************************************************************
 * DiscourseDownloadStore.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * The durable side of downloads (AGENTS.md section 7): one `<audioID>.audio`
 * file per track under Application Support/Discourses, a JSON map from audio id
 * to filename and a reverse map from audio id to discourse id. Reads verify the
 * file on disk (exists and is not empty) so a half-written or externally deleted
 * file falls back to streaming instead of failing playback. Records whose file
 * vanished are pruned on launch, and files no record mentions are deleted, so
 * neither side can leak.
 *****************************************************************************/

import Foundation

final class DiscourseDownloadStore {
    static let shared = DiscourseDownloadStore()

    static let downloadsKey = "osho_api_discourse_downloads"
    static let discoursesKey = "osho_api_discourse_download_discourses"

    private let settings: DiscourseSettings
    private let fileManager: FileManager
    private let directoryURL: URL
    private let queue = DispatchQueue(label: "online.sandalbar.rajneesh-discourse.downloads.store")

    /// audioID → filename on disk.
    private var files: [String: String]
    /// audioID → discourseID, so a discourse can list and remove its tracks.
    private var discourses: [String: String]

    init(settings: DiscourseSettings = .shared,
         fileManager: FileManager = .default,
         directoryURL: URL? = nil) {
        self.settings = settings
        self.fileManager = fileManager

        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory,
                                        in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.directoryURL = base.appendingPathComponent("Discourses", isDirectory: true)
        }

        files = settings.decode([String: String].self, forKey: Self.downloadsKey) ?? [:]
        discourses = settings.decode([String: String].self, forKey: Self.discoursesKey) ?? [:]

        createDirectory()
        pruneMissingFiles()
        removeOrphanFiles()
    }

    // MARK: - Reading

    var directory: URL {
        return directoryURL
    }

    /// The local file for `audioID`, or `nil` when there is no verified copy.
    /// Playback uses this to prefer the download and to fall back to streaming.
    func localURL(for audioID: String) -> URL? {
        let filename: String? = queue.sync { files[audioID] }
        guard let filename else {
            return nil
        }
        let url = directoryURL.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: url.path),
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0 else {
            return nil
        }
        return url
    }

    func isDownloaded(audioID: String) -> Bool {
        return localURL(for: audioID) != nil
    }

    func filename(for audioID: String) -> String? {
        return queue.sync { files[audioID] }
    }

    func discourseID(for audioID: String) -> String? {
        return queue.sync { discourses[audioID] }
    }

    func downloadedAudioIDs(forDiscourse discourseID: String) -> Set<String> {
        return queue.sync {
            Set(discourses.compactMap { audioID, owner in
                owner == discourseID ? audioID : nil
            })
        }
    }

    func downloadedCount(forDiscourse discourseID: String) -> Int {
        return queue.sync {
            discourses.reduce(into: 0) { count, entry in
                if entry.value == discourseID {
                    count += 1
                }
            }
        }
    }

    // MARK: - Writing

    /// Moves a finished URLSession download into the downloads directory and
    /// records it. Throws when the move fails, so the caller can mark the track
    /// failed instead of recording a file that is not there.
    func storeDownloadedFile(at location: URL,
                             audioID: String,
                             discourseID: String) throws {
        createDirectory()

        let name = Self.filename(for: audioID)
        let destination = directoryURL.appendingPathComponent(name)
        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: location, to: destination)

        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDestination = destination
        try? mutableDestination.setResourceValues(values)

        queue.sync {
            files[audioID] = name
            if !discourseID.isEmpty {
                discourses[audioID] = discourseID
            }
            persist()
        }
    }

    /// Deletes the file and both records. Returns `true` when something was
    /// removed.
    @discardableResult
    func remove(audioID: String) -> Bool {
        var filename: String?
        queue.sync {
            filename = files.removeValue(forKey: audioID)
            discourses.removeValue(forKey: audioID)
            persist()
        }
        guard let filename else {
            return false
        }
        try? fileManager.removeItem(at: directoryURL.appendingPathComponent(filename))
        return true
    }

    /// Removes every downloaded track of one discourse. Returns the number of
    /// records removed.
    @discardableResult
    func removeAll(forDiscourse discourseID: String) -> Int {
        var removed: [String: String] = [:]
        queue.sync {
            for (audioID, owner) in discourses where owner == discourseID {
                if let filename = files[audioID] {
                    removed[audioID] = filename
                }
            }
            for audioID in removed.keys {
                files.removeValue(forKey: audioID)
                discourses.removeValue(forKey: audioID)
            }
            persist()
        }
        for filename in removed.values {
            try? fileManager.removeItem(at: directoryURL.appendingPathComponent(filename))
        }
        return removed.count
    }

    @discardableResult
    func removeAll() -> Int {
        var removed: [String: String] = [:]
        queue.sync {
            removed = files
            files.removeAll()
            discourses.removeAll()
            persist()
        }
        for filename in removed.values {
            try? fileManager.removeItem(at: directoryURL.appendingPathComponent(filename))
        }
        return removed.count
    }

    // MARK: - Housekeeping

    private func createDirectory() {
        try? fileManager.createDirectory(at: directoryURL,
                                         withIntermediateDirectories: true,
                                         attributes: nil)
    }

    private static func filename(for audioID: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let sanitized = audioID.unicodeScalars
            .filter { allowed.contains($0) }
            .map(String.init)
            .joined()
        let name = sanitized.isEmpty ? UUID().uuidString : sanitized
        return "\(name).audio"
    }

    /// Drops records whose file is missing or empty (never the other way round:
    /// a file without a record is deleted by `removeOrphanFiles`).
    private func pruneMissingFiles() {
        queue.sync {
            var changed = false
            for (audioID, filename) in files {
                let url = directoryURL.appendingPathComponent(filename)
                guard fileManager.fileExists(atPath: url.path),
                      let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                      size > 0 else {
                    files.removeValue(forKey: audioID)
                    discourses.removeValue(forKey: audioID)
                    changed = true
                    continue
                }
            }
            if changed {
                persist()
            }
        }
    }

    /// Deletes files nothing points at (a crash between moving the file and
    /// writing the record, or a record removed outside the store).
    private func removeOrphanFiles() {
        let known = Set(queue.sync { Array(files.values) })
        guard let contents = try? fileManager.contentsOfDirectory(atPath: directoryURL.path) else {
            return
        }
        for name in contents where !known.contains(name) {
            try? fileManager.removeItem(at: directoryURL.appendingPathComponent(name))
        }
    }

    private func persist() {
        settings.encode(files, forKey: Self.downloadsKey)
        settings.encode(discourses, forKey: Self.discoursesKey)
    }
}
