/*****************************************************************************
 * DiscourseDiagnostics.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * This fork does not ship a telemetry SDK (see AGENTS.md section 10.2).
 * Unexpected failures are logged to the system log with a `Discourse` category
 * and a screen/context tag. Expected offline, cancellation and 4xx results are
 * not errors and must not be logged as such. Never pass the API key, the
 * anonymous user UUID or auth headers to these helpers.
 *****************************************************************************/

import Foundation

enum DiscourseDiagnostics {
    enum Level: String {
        case info
        case warning
        case error
    }

    /// Set to `false` in tests to keep the log clean.
    static var isEnabled = true

    static func log(_ message: @autoclosure () -> String,
                    level: Level = .error,
                    context: String? = nil) {
        guard isEnabled else {
            return
        }
        let tag = context.map { "[\($0)] " } ?? ""
        NSLog("[Discourse][\(level.rawValue)] \(tag)\(message())")
    }
}
