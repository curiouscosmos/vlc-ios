/*****************************************************************************
 * DiscourseDownloadActions.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * One place for the download tap and menu semantics so every row, card and
 * screen behaves the same: a tap downloads, cancels a running download or
 * retries a failed one or removes a completed download, and
 * removing a whole discourse asks first (AGENTS.md section 6.6).
 *****************************************************************************/

import UIKit

@MainActor
enum DiscourseDownloadActions {
    /// Tap on the row's download control.
    static func toggle(_ track: DiscourseAudio, discourseID: String? = nil) {
        let manager = DiscourseDownloadManager.shared
        switch manager.state(for: track.id) {
        case .missing, .failed:
            manager.download(track, discourseID: discourseID)
        case .downloading:
            manager.cancel(audioID: track.id)
        case .downloaded:
            manager.remove(audioID: track.id)
        }
    }

    static func remove(_ track: DiscourseAudio) {
        DiscourseDownloadManager.shared.remove(audioID: track.id)
    }

    /// Asks before deleting every downloaded track of a discourse.
    static func confirmRemoveAll(in viewController: UIViewController,
                                 discourseID: String,
                                 discourseTitle: String,
                                 completion: (() -> Void)? = nil) {
        let title = NSLocalizedString("DISCOURSE_DOWNLOAD_REMOVE_ALL_CONFIRM",
                                      comment: "Confirmation before deleting every downloaded track of a discourse")
        let alert = UIAlertController(title: title,
                                      message: discourseTitle,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("BUTTON_CANCEL",
                                                               comment: "Cancel a destructive action"),
                                      style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("DISCOURSE_DOWNLOAD_REMOVE_ALL_ACTION",
                                                               comment: "Confirm deleting every downloaded track of a discourse"),
                                      style: .destructive) { _ in
            DiscourseDownloadManager.shared.removeAll(discourseID: discourseID)
            completion?()
        })
        viewController.present(alert, animated: true)
    }

    /// The context-menu entry for one track, matching its current state.
    static func menuAction(for track: DiscourseAudio,
                           discourseID: String? = nil) -> UIAction? {
        switch DiscourseDownloadManager.shared.state(for: track.id) {
        case .missing:
            return UIAction(title: NSLocalizedString("DISCOURSE_DOWNLOAD_MENU",
                                                     comment: "Download a track"),
                            image: UIImage(systemName: "arrow.down.circle")) { _ in
                DiscourseDownloadManager.shared.download(track, discourseID: discourseID)
            }
        case .downloading:
            return UIAction(title: NSLocalizedString("DISCOURSE_DOWNLOAD_CANCEL_MENU",
                                                     comment: "Cancel a running track download"),
                            image: UIImage(systemName: "xmark.circle")) { _ in
                DiscourseDownloadManager.shared.cancel(audioID: track.id)
            }
        case .downloaded:
            return UIAction(title: NSLocalizedString("DISCOURSE_DOWNLOAD_REMOVE_MENU",
                                                     comment: "Delete a downloaded track"),
                            image: UIImage(systemName: "trash"),
                            attributes: .destructive) { _ in
                DiscourseDownloadManager.shared.remove(audioID: track.id)
            }
        case .failed:
            return UIAction(title: NSLocalizedString("DISCOURSE_DOWNLOAD_RETRY_MENU",
                                                     comment: "Retry a failed track download"),
                            image: UIImage(systemName: "arrow.clockwise")) { _ in
                DiscourseDownloadManager.shared.download(track, discourseID: discourseID)
            }
        }
    }
}
