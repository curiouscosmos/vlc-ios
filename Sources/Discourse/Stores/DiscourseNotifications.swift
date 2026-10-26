/*****************************************************************************
 * DiscourseNotifications.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * Store changes are broadcast through NotificationCenter, mirroring the
 * existing VLC pattern (`.VLCThemeDidChangeNotification`). Screens observe the
 * names they care about instead of polling the stores.
 *****************************************************************************/

import Foundation

extension Notification.Name {
    /// Liked sets, like counts or pending toggles changed.
    static let discourseLikesDidChange = Notification.Name("discourseLikesDidChange")
    /// The recently played discourses or tracks changed.
    static let discourseHistoryDidChange = Notification.Name("discourseHistoryDidChange")
    /// A playback position, completion or played state changed.
    static let discoursePlaybackProgressDidChange = Notification.Name("discoursePlaybackProgressDidChange")
    /// A download started, progressed, finished, failed or was removed.
    static let discourseDownloadsDidChange = Notification.Name("discourseDownloadsDidChange")
    /// The Audio Mixer's membership, selection, switches or playback changed.
    static let discourseMixerDidChange = Notification.Name("discourseMixerDidChange")
    /// A fork screen asked to reveal the Discourses tab's Local library.
    static let discourseShowLocalLibrary = Notification.Name("discourseShowLocalLibrary")
}
