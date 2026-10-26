/*****************************************************************************
 * DiscourseURLResolver.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * The backend stores media paths as either absolute URLs or paths relative to
 * the CDN. Both forms are normalised here, and anything that is not HTTPS is
 * rejected so the player never receives a cleartext or unknown-scheme URL.
 *****************************************************************************/

import Foundation

enum DiscourseURLResolver {
    /// CDN root used for relative paths returned by the API.
    static let cdnBaseURL = URL(string: "https://osho.b-cdn.net/OSHO/")!

    /// Resolves an API `*_url` value into a playable/downloadable URL.
    ///
    /// - absolute `https://…` URLs are returned unchanged;
    /// - relative paths are resolved against `cdnBaseURL`;
    /// - `http://`, `file://`, `data:` and every other scheme are rejected.
    static func resolve(_ rawValue: String?) -> URL? {
        guard let rawValue else {
            return nil
        }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }

        if hasScheme(value) {
            guard let url = URL(string: value), url.scheme?.lowercased() == "https" else {
                return nil
            }
            return url
        }

        let relative = value.drop(while: { $0 == "/" })
        // Keep existing percent escapes (the backend may pre-encode) while
        // escaping characters such as spaces. This mirrors the Android
        // reference, which resolves the same values with `java.net.URI`.
        var allowed = CharacterSet.urlPathAllowed
        allowed.insert(charactersIn: "%")
        guard !relative.isEmpty,
              let escaped = relative.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: escaped, relativeTo: cdnBaseURL) else {
            return nil
        }
        return url.absoluteURL
    }

    /// True when the value starts with an RFC 3986 scheme (`https:`, `ftp:`, `file:` …).
    static func hasScheme(_ value: String) -> Bool {
        guard let first = value.first, first.isASCII, first.isLetter else {
            return false
        }
        for character in value.dropFirst() {
            if character == ":" {
                return true
            }
            let isAllowed = character.isASCII && (character.isLetter || character.isNumber
                || character == "+" || character == "-" || character == ".")
            if !isAllowed {
                return false
            }
        }
        return false
    }
}
