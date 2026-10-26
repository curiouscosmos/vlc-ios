/*****************************************************************************
 * DiscourseAccessibilityButton.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * A transparent accessibility element that opens the card/row it covers.
 * Touch handling stays with the hosting cell (the view is not interactive), so
 * collection/table selection keeps working exactly as before, while VoiceOver
 * gets a proper button element next to the row's like control instead of one
 * merged element that hides it.
 *****************************************************************************/

import UIKit

final class DiscourseAccessibilityButton: UIView {
    var onActivate: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = .button
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func accessibilityActivate() -> Bool {
        guard let onActivate else {
            return false
        }
        onActivate()
        return true
    }
}
