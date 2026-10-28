/*****************************************************************************
 * DiscourseDeepLink.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * Parses the website's share links:
 *
 *   https://rajneeshdiscourse.com/discourses/{discourseID}
 *   https://rajneeshdiscourse.com/discourses/{discourseID}/tracks/{audioID}
 *
 * The same shape as the Android reference's `DiscourseLinks.kt`. Only the
 * website host is accepted; unrelated https URLs must fall through to Safari.
 *****************************************************************************/

import Foundation

@objc(VLCDiscourseDeepLink)
final class DiscourseDeepLink: NSObject {
    @objc let discourseID: String
    @objc let audioID: String?

    @objc init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host?.lowercased(),
              host == "rajneeshdiscourse.com" || host == "www.rajneeshdiscourse.com" else {
            return nil
        }

        let segments = url.pathComponents.filter { $0 != "/" }
        guard segments.count == 2 || segments.count == 4,
              segments[0].caseInsensitiveCompare("discourses") == .orderedSame else {
            return nil
        }

        let discourseID = segments[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !discourseID.isEmpty else {
            return nil
        }

        var audioID: String?
        if segments.count == 4 {
            guard segments[2].caseInsensitiveCompare("tracks") == .orderedSame else {
                return nil
            }
            let trimmedAudioID = segments[3].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedAudioID.isEmpty else {
                return nil
            }
            audioID = trimmedAudioID
        }

        self.discourseID = discourseID
        self.audioID = audioID
        super.init()
    }

    /// ObjC-callable check used by `VLCAppCoordinator` before queueing a URL.
    @objc static func canHandle(_ url: URL) -> Bool {
        return DiscourseDeepLink(url: url) != nil
    }

    /// Builds the public website URL for a track, exactly the shape the app
    /// already parses from Universal Links.
    @objc static func trackURL(discourseID: String, audioID: String) -> URL? {
        let discourseID = discourseID.trimmingCharacters(in: .whitespacesAndNewlines)
        let audioID = audioID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !discourseID.isEmpty, !audioID.isEmpty else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "rajneeshdiscourse.com"
        components.path = "/discourses/\(discourseID)/tracks/\(audioID)"
        return components.url
    }
}
