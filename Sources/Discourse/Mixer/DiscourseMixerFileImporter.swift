/*****************************************************************************
 * DiscourseMixerFileImporter.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * Copies a file chosen in the system document picker into app-owned storage.
 * A picker URL can lose its security scope after relaunch, so the mixer keeps
 * the copy instead of the original URL. The source URL determines a stable
 * subdirectory and the original filename is preserved for the row title.
 *****************************************************************************/

import CryptoKit
import Foundation

struct DiscourseMixerFileImporter {
    enum ImportError: Error {
        case invalidFile
    }

    private let fileManager: FileManager
    private let directory: URL

    init(fileManager: FileManager = .default,
         directory: URL = DiscourseMixerFileImporter.defaultDirectory()) {
        self.fileManager = fileManager
        self.directory = directory.standardizedFileURL
    }

    /// Copies `sourceURL` into the mixer directory, or returns the copy already
    /// made for that source. Repeated imports therefore remain idempotent.
    func `import`(_ sourceURL: URL) throws -> URL {
        guard sourceURL.isFileURL else {
            throw ImportError.invalidFile
        }

        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw ImportError.invalidFile
        }

        let destinationDirectory = directory.appendingPathComponent(Self.sourceID(for: sourceURL),
                                                                       isDirectory: true)
        let destination = destinationDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        if fileManager.fileExists(atPath: destination.path) {
            return destination
        }

        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let temporary = destinationDirectory.appendingPathComponent(".\(UUID().uuidString).part")
        do {
            try fileManager.copyItem(at: sourceURL, to: temporary)
            guard let attributes = try? fileManager.attributesOfItem(atPath: temporary.path),
                  let size = attributes[.size] as? NSNumber,
                  size.int64Value > 0 else {
                throw ImportError.invalidFile
            }
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: destination)
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            removeDirectoryIfEmpty(destinationDirectory)
            throw error
        }
        return destination
    }

    /// Deletes an app-owned import and its now-empty source directory. URLs from
    /// the media library or elsewhere on disk are never touched.
    func removeImportedFile(at url: URL) {
        guard owns(url) else {
            return
        }
        try? fileManager.removeItem(at: url)
        removeDirectoryIfEmpty(url.deletingLastPathComponent().standardizedFileURL)
    }

    private func removeDirectoryIfEmpty(_ directory: URL) {
        guard directory != self.directory,
              let contents = try? fileManager.contentsOfDirectory(atPath: directory.path),
              contents.isEmpty else {
            return
        }
        try? fileManager.removeItem(at: directory)
    }

    private func owns(_ url: URL) -> Bool {
        guard url.isFileURL else {
            return false
        }
        let root = directory.path
        let path = url.standardizedFileURL.path
        return path.hasPrefix(root + "/")
    }

    private static func sourceID(for url: URL) -> String {
        let source = url.standardizedFileURL.absoluteString
        let digest = SHA256.hash(data: Data(source.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    private static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("AudioMixer", isDirectory: true)
    }
}
