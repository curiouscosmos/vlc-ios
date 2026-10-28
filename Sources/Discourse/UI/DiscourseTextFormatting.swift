/*****************************************************************************
 * DiscourseTextFormatting.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * Shared copy for catalogue cards, the discourse detail header and the track
 * rows: language names, singular/plural counts, the "language · tracks · likes"
 * summary line, and track durations. All user-facing text is localised here so
 * the screens never hard-code English (AGENTS.md 5.4).
 *****************************************************************************/

import Foundation

enum DiscourseDurationFormatter {
    /// `0:42`, `12:05`, `1:02:03`. Returns `nil` when the duration is unknown,
    /// negative or not finite, so callers can hide the label.
    static func string(forSeconds seconds: Double?) -> String? {
        guard let seconds, seconds.isFinite, seconds >= 0 else {
            return nil
        }

        let total = Int(seconds.rounded())
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remaining = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remaining)
        }
        return String(format: "%d:%02d", minutes, remaining)
    }
}

enum DiscourseMetadataText {
    /// `english` → `English`; unknown values keep their capitalisation.
    static func language(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }
        if let language = DiscourseLanguage(rawValue: trimmed.lowercased()) {
            return language.displayName
        }
        return trimmed.localizedCapitalized
    }

    static func tracks(_ count: Int) -> String {
        if count == 1 {
            return NSLocalizedString("DISCOURSE_CARD_TRACK_ONE",
                                     comment: "Track count of exactly one")
        }
        return String(format: NSLocalizedString("DISCOURSE_CARD_TRACKS",
                                                comment: "Track count"),
                      max(0, count))
    }

    static func likes(_ count: Int) -> String {
        if count == 1 {
            return NSLocalizedString("DISCOURSE_CARD_LIKE_ONE",
                                     comment: "Like count of exactly one")
        }
        return String(format: NSLocalizedString("DISCOURSE_CARD_LIKES",
                                                comment: "Like count"),
                      DiscourseCountFormatter.string(for: count))
    }

    /// `English · 11 tracks · 1 like`, skipping unknown parts.
    static func summary(language rawLanguage: String, tracks trackCount: Int, likes likeCount: Int) -> String {
        let languageName = language(rawLanguage)
        var parts: [String] = []
        if !languageName.isEmpty {
            parts.append(languageName)
        }
        parts.append(tracks(trackCount))
        if likeCount > 0 {
            parts.append(likes(likeCount))
        }
        return parts.joined(separator: " · ")
    }
}
