/*****************************************************************************
 * DiscourseLocalLibraryViewController.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * The local audio library opened from local-media shortcuts. It is not a Mixer
 * destination. The upstream audio pager is reduced to Songs and Folders while
 * the library's own navigation-bar actions (search, select all, sort, renderer,
 * settings, history) keep working.
 *****************************************************************************/

import UIKit

final class DiscourseLocalLibraryViewController: AudioViewController {
    override func viewControllers(for pagerTabStripController: PagerTabStripViewController) -> [UIViewController] {
        let songs = TrackCategoryViewController(mediaLibraryService)
        songs.tabSearchScope = .audio
        songs.showsLocalAudioEmptyState = true
        let folders = FolderViewController(mediaLibraryService,
                                           isAudio: true,
                                           folder: mediaLibraryService.baseFolder())
        return [songs, folders]
    }

    override func viewWillAppear(_ animated: Bool) {
        // The upstream pages save five-page indices; preserve this pager's index.
        UserDefaults.standard.set(currentIndex, forKey: kVLCAudioTabIndex)
        super.viewWillAppear(animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        view.layoutIfNeeded()
        if containerView.bounds.width > 0 {
            updateContent()
        }
        (viewControllers.first as? MediaCategoryViewController)?.updateEmptyState()
    }
}
