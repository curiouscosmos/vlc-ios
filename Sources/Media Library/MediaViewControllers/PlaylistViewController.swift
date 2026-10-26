/*****************************************************************************
 * VLCPlaylistViewController.swift
 * VLC for iOS
 *****************************************************************************
 * Copyright (c) 2018 VideoLAN. All rights reserved.
 * $Id$
 *
 * Authors: Carola Nitz <caro # videolan.org>
 *
 * Refer to the COPYING file of the official project for license.
 *****************************************************************************/

class PlaylistViewController: MediaViewController {
    override init(mediaLibraryService: MediaLibraryService) {
        super.init(mediaLibraryService: mediaLibraryService)
        setupUI()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyForkTheme()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applyForkTheme),
                                               name: .VLCThemeDidChangeNotification,
                                               object: nil)
    }

    /// The fork's playlists tab uses the discourse accent for its bar buttons
    /// (the upstream orange is still the global tint for the library).
    @objc private func applyForkTheme() {
        navigationController?.navigationBar.tintColor = DiscourseColors.current.accent
    }

    private func setupUI() {
        title = NSLocalizedString("PLAYLISTS", comment: "")
        tabBarItem = UITabBarItem(
            title: NSLocalizedString("PLAYLISTS", comment: ""),
            image: UIImage(named: "Playlist"),
            selectedImage: UIImage(named: "Playlist"))
        tabBarItem.accessibilityIdentifier = VLCAccessibilityIdentifier.playlist
    }

    override func viewControllers(for pagerTabStripController: PagerTabStripViewController) -> [UIViewController] {
        return [
            PlaylistCategoryViewController(mediaLibraryService)
        ]
    }

    func resetTitleView() {
        navigationItem.titleView = nil
    }
}
