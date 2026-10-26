/*****************************************************************************
 * DiscoursePlaybackSettings.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * The fork's playback-history switch. It reuses the Android reference's
 * `playback_history` key and defaults to on (the key has no value until the user
 * changes it), so the behaviour is comparable across both apps. The Home screen
 * hides the recently-played tracks section while it is off; the playback
 * integration (Phase 10) also stops recording history and posting stats.
 *****************************************************************************/

import Foundation

enum DiscoursePlaybackSettings {
    /// Matches the Android reference's `playback_history` preference.
    static let historyKey = "playback_history"

    static var isHistoryEnabled: Bool {
        UserDefaults.standard.object(forKey: historyKey) as? Bool ?? true
    }
}
