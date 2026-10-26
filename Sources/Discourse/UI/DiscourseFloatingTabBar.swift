/*****************************************************************************
 * DiscourseFloatingTabBar.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * iOS 26's tab bar floats above the content as a Liquid Glass capsule instead
 * of sitting below it, so a scroll view pinned to the view's edges needs the
 * covered height added to its bottom inset. On earlier systems the classic bar
 * is part of the safe area and contributes nothing.
 *****************************************************************************/

import UIKit

extension UIViewController {
    /// The height of the screen currently covered by a floating tab bar, or 0
    /// on systems whose tab bar does not float.
    var discourseFloatingTabBarInset: CGFloat {
        guard #available(iOS 26.0, *),
              let tabBar = tabBarController?.tabBar,
              tabBar.window != nil else {
            return 0
        }
        let frame = tabBar.convert(tabBar.bounds, to: view)
        return max(0, view.bounds.height - frame.minY)
    }
}
