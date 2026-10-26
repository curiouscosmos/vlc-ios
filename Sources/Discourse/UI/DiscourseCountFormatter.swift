/*****************************************************************************
 * DiscourseCountFormatter.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * Compact count formatting shared by the catalogue, the track rows and the
 * player: 999, 1.2k, 12k, 1m, 1.2m. The product brief fixes these shapes, so the
 * formatter is kept free of locale-specific separators on purpose.
 *****************************************************************************/

import Foundation

enum DiscourseCountFormatter {
    /// Formats a non-negative count the way the catalogue and the like controls
    /// display it: `999`, `1k`, `1.2k`, `12k`, `1m`, `1.2m`.
    static func string(for count: Int) -> String {
        let value = max(0, count)

        guard value >= 1_000 else {
            return String(value)
        }

        if value < 1_000_000 {
            let thousands = Double(value) / 1_000
            if thousands < 9.95 {
                return decimal(thousands, unit: "k")
            }
            if thousands < 999.5 {
                return "\(Int(thousands.rounded()))k"
            }
            return "1m"
        }

        return decimal(Double(value) / 1_000_000, unit: "m")
    }

    /// One decimal below ten (`1.2k`), whole numbers above (`12k`), and never a
    /// trailing `.0`.
    private static func decimal(_ value: Double, unit: String) -> String {
        if value >= 9.95 {
            return "\(Int(value.rounded()))\(unit)"
        }
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return "\(Int(rounded))\(unit)"
        }
        return String(format: "%.1f%@", rounded, unit)
    }
}
