/*****************************************************************************
 * TabBarCoordinator.swift
 * VLC for iOS
 *****************************************************************************
 * Copyright (c) 2018 VideoLAN. All rights reserved.
 * $Id$
 *
 * Authors: Carola Nitz <nitz.carola # gmail.com>
 *          Diogo Simao Marques <dogo@videolabs.io>
 *
 * Refer to the COPYING file of the official project for license.
 *****************************************************************************/

import UIKit

class TabBarCoordinator: NSObject {
    // MARK: - Properties

    /// The five Rajneesh Discourse destinations, in product order. The raw value
    /// is the tab bar index and the value persisted under `TabBarIndex`.
    private enum Destination: Int {
        case home
        case discourses
        case search
        case playlists
        case mixer
    }

    private var tabBarController: BottomTabBarController
    private var mediaLibraryService: MediaLibraryService

    private var editToolbar: EditToolbar?
    private var sideToolBar: EditToolbar?

    private lazy var homeNavigationController = makeNavigationController(
        root: DiscourseHomeViewController(mediaLibrary: mediaLibraryService),
        title: NSLocalizedString("HOME", comment: "Home tab title"),
        systemImage: "house",
        identifier: VLCAccessibilityIdentifier.home)

    private lazy var catalogueViewController = DiscourseCatalogueViewController()

    /// The device audio browser, shown by the Discourses tab's "Local" segment.
    /// It is the upstream screen, so its bar buttons, edit mode and pager keep
    /// working; the segment swaps the tab's navigation root instead of embedding
    /// the browser as a child (a child would lose its navigation-bar actions).
    private lazy var localLibraryViewController: AudioViewController = {
        let controller = AudioViewController(mediaLibraryService: mediaLibraryService)
        controller.title = NSLocalizedString("DISCOURSE_LOCAL_LIBRARY",
                                             comment: "Title of the device audio library")
        return controller
    }()

    /// Discourse / Local switch, shown in the navigation bar of both roots.
    private lazy var librarySegment: UISegmentedControl = {
        let control = UISegmentedControl(items: [
            NSLocalizedString("DISCOURSES_SEGMENT_DISCOURSE", comment: "Remote catalogue segment"),
            NSLocalizedString("DISCOURSES_SEGMENT_LOCAL", comment: "Device library segment")
        ])
        control.selectedSegmentIndex = LibrarySegment.discourses.rawValue
        control.addTarget(self, action: #selector(librarySegmentChanged(_:)), for: .valueChanged)
        control.accessibilityIdentifier = "discoursesSegment"
        return control
    }()

    private enum LibrarySegment: Int {
        case discourses
        case local
    }

    private lazy var discoursesNavigationController = makeNavigationController(
        root: catalogueViewController,
        title: NSLocalizedString("DISCOURSES", comment: "Discourses tab title"),
        systemImage: "book.closed",
        identifier: VLCAccessibilityIdentifier.discourses)

    private lazy var searchNavigationController = makeNavigationController(
        root: DiscourseSearchViewController(),
        title: NSLocalizedString("SEARCH", comment: "Search tab title"),
        systemImage: "magnifyingglass",
        identifier: VLCAccessibilityIdentifier.search)

    private lazy var playlistsNavigationController = makeNavigationController(
        root: PlaylistViewController(mediaLibraryService: mediaLibraryService),
        title: NSLocalizedString("PLAYLISTS", comment: ""),
        systemImage: "music.note.list",
        identifier: VLCAccessibilityIdentifier.playlist)

    private lazy var mixerNavigationController = makeNavigationController(
        root: DiscourseAudioMixerViewController(),
        title: NSLocalizedString("AUDIO_MIXER", comment: "Audio Mixer tab title"),
        systemImage: "slider.horizontal.3",
        identifier: VLCAccessibilityIdentifier.audioMixer)

    // MARK: - Init

    @objc init(tabBarController: BottomTabBarController, mediaLibraryService: MediaLibraryService) {
        self.tabBarController = tabBarController
        self.mediaLibraryService = mediaLibraryService
        super.init()
        setup()
        NotificationCenter.default.addObserver(self, selector: #selector(updateTheme), name: .VLCThemeDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDidEnterBackgroundNotification),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshDiscourseLikes),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
        mediaLibraryService.observable.addObserver(self)
    }

    /// The spec refreshes the liked sets from `GET /likes` at most once every
    /// seven days; the store gates that, so a call on launch and on every
    /// foreground is cheap.
    @objc private func refreshDiscourseLikes() {
        Task {
            do {
                _ = try await DiscourseLikesStore.shared.refresh()
            } catch {
                DiscourseDiagnostics.log("likes refresh failed",
                                         level: .info,
                                         context: "Likes")
            }
        }
    }

    // MARK: - Setup methods

    private func setup() {
        tabBarController.delegate = self
        setupViewControllers()
        // Resume points, progress, completion and the 60 s stats/history
        // qualification are driven from the upstream playback notifications.
        Task { @MainActor in
            DiscoursePlaybackTracker.shared.start()
        }
        // The mixer follows the main player from launch, not from the first time
        // its tab is opened, so a previously enabled mixer keeps working.
        _ = DiscourseAudioMixer.shared
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(revealLocalLibrary),
                                               name: .discourseShowLocalLibrary,
                                               object: nil)
        refreshDiscourseLikes()
        tabBarController.editToolbarSetupHandler = { [weak self] in
            self?.setupEditToolbar()
        }
        updateTheme()
        tabBarController.title = "Rajneesh Discourse"
#if os(iOS)
        // The sidebar chrome is an iPad layout. On iPhone the default tab-bar
        // mode is required, otherwise iOS 26 falls back to the legacy bar
        // instead of the floating Liquid Glass capsule.
        if #available(iOS 18.0, *), UIDevice.current.userInterfaceIdiom == .pad {
            tabBarController.mode = .tabSidebar
            let sideBar = tabBarController.sidebar
            sideBar.preferredLayout = .overlap
            sideBar.delegate = self
            sideBar.bottomBarView?.isHidden = true
        }
#endif
#if os(iOS)
        updateTabBarIndexIfNeeded()
#else
        tabBarController.selectedIndex = max(UserDefaults.standard.integer(forKey: kVLCTabBarIndex), 0)
#endif
    }

    private func setupViewControllers() {
        // Exactly five destinations: Home, Discourses, Search, Playlists and the
        // Audio Mixer. Videos, Browse, On Air and the separate Audio library tab
        // are not part of the product surface; the device library opens from the
        // Discourses tab.
        tabBarController.viewControllers = [
            homeNavigationController,
            discoursesNavigationController,
            searchNavigationController,
            playlistsNavigationController,
            mixerNavigationController
        ]

        installLibraryRoot(.discourses, animated: false)
    }

    // MARK: - Discourses / Local

    @objc private func librarySegmentChanged(_ sender: UISegmentedControl) {
        guard let segment = LibrarySegment(rawValue: sender.selectedSegmentIndex) else {
            return
        }
        installLibraryRoot(segment, animated: false)
    }

    /// Swaps the Discourses tab between the remote catalogue and the device
    /// library. Both view controllers are kept alive, so the library keeps its
    /// pager and scroll position while the catalogue is on screen.
    private func installLibraryRoot(_ segment: LibrarySegment, animated: Bool) {
        let root: UIViewController
        switch segment {
        case .discourses:
            root = catalogueViewController
            localLibraryViewController.navigationItem.titleView = nil
        case .local:
            root = localLibraryViewController
            catalogueViewController.navigationItem.titleView = nil
        }

        root.navigationItem.titleView = librarySegment
        librarySegment.selectedSegmentIndex = segment.rawValue

        guard discoursesNavigationController.viewControllers.first !== root else {
            return
        }
        discoursesNavigationController.setViewControllers([root], animated: animated)
    }

    private func makeNavigationController(root: UIViewController,
                                          title: String,
                                          systemImage: String,
                                          identifier: String) -> UINavigationController {
        let navigationController = UINavigationController(rootViewController: root)
        navigationController.navigationBar.accessibilityIdentifier = identifier
        let image = UIImage(systemName: systemImage)
        let tabBarItem = UITabBarItem(title: title, image: image, selectedImage: image)
        tabBarItem.accessibilityIdentifier = identifier
        navigationController.tabBarItem = tabBarItem
        return navigationController
    }

#if os(iOS)
    private func updateTabBarIndexIfNeeded() {
        let userDefaults = UserDefaults.standard
        // Flat tab index: 0 Home, 1 Discourses, 2 Search, 3 Playlists, 4 Audio Mixer.
        let tabCount = tabBarController.viewControllers?.count ?? 1
        let index = min(max(userDefaults.integer(forKey: kVLCTabBarIndex), 0), max(tabCount - 1, 0))
        tabBarController.selectedIndex = index
        userDefaults.set(index, forKey: kVLCTabBarIndex)
    }
#endif

    func setupEditToolbar() {
        let colors = PresentationTheme.current.colors
        let editToolbar = EditToolbar()
        self.editToolbar = editToolbar
        editToolbar.isHidden = true
        editToolbar.translatesAutoresizingMaskIntoConstraints = false
        editToolbar.backgroundColor = colors.tabBarColor

        var useSidebar = false
#if os(iOS)
        if #available(iOS 18.0, *), UIDevice.current.userInterfaceIdiom == .pad {
            let sideToolBar = EditToolbar()
            self.sideToolBar = sideToolBar
            sideToolBar.isHidden = true
            sideToolBar.translatesAutoresizingMaskIntoConstraints = false
            sideToolBar.backgroundColor = colors.tabBarColor
            tabBarController.sidebar.bottomBarView = sideToolBar
            useSidebar = true
        }
#endif
        if !useSidebar {
            let containerView = tabBarController.view!
            containerView.addSubview(editToolbar)

            NSLayoutConstraint.activate([
                editToolbar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                editToolbar.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                editToolbar.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
                editToolbar.topAnchor.constraint(equalTo: tabBarController.tabBar.topAnchor),
            ])
        }
    }

    // MARK: - Helpers

    @objc func updateTheme() {
        let colors = PresentationTheme.current.colors
        let tabBar = tabBarController.tabBar
        let bottomBar = tabBarController.bottomBar

#if os(iOS)
        tabBar.isTranslucent = true
        bottomBar.isTranslucent = false
#endif

        // The fork's accent on the capsule (and on the classic bar below iOS 26).
        let discourseColors = DiscourseColors.current
        tabBar.tintColor = discourseColors.accent
        tabBar.unselectedItemTintColor = discourseColors.secondaryText

        if #unavailable(iOS 26.0) {
            let tabBarLayer = tabBar.layer
            let bottomBarLayer = bottomBar.layer

            //Setting this in appearanceManager doesn't update tabbar and UINavigationbar of the settingsViewController on change hence we do it here
            tabBar.backgroundColor = colors.tabBarColor
            tabBar.barTintColor = colors.tabBarColor
            tabBar.itemPositioning = .fill

            bottomBar.backgroundColor = colors.tabBarColor
            bottomBar.barTintColor = colors.tabBarColor
            bottomBar.itemPositioning = .fill

            tabBarLayer.shadowOffset = CGSize(width: 0, height: 0)
            tabBarLayer.shadowRadius = 1.0
            tabBarLayer.shadowColor = colors.cellDetailTextColor.cgColor
            tabBarLayer.shadowOpacity = 0.6
            tabBarLayer.shadowPath = UIBezierPath(rect: tabBar.bounds).cgPath

            bottomBarLayer.shadowOffset = CGSize(width: 0, height: 0)
            bottomBarLayer.shadowRadius = 1.0
            bottomBarLayer.shadowColor = colors.cellDetailTextColor.cgColor
            bottomBarLayer.shadowOpacity = 0.6
            bottomBarLayer.shadowPath = UIBezierPath(rect: bottomBar.bounds).cgPath

            tabBarController.view.backgroundColor = colors.background
        }

        editToolbar?.backgroundColor = colors.tabBarColor
        sideToolBar?.backgroundColor = colors.tabBarColor

        if #unavailable(iOS 26.0) {
            UINavigationBar.appearance().standardAppearance = AppearanceManager.navigationbarAppearance()
            UINavigationBar.appearance().compactAppearance = AppearanceManager.navigationbarAppearance()
            UINavigationBar.appearance().scrollEdgeAppearance = AppearanceManager.navigationbarAppearance()
        }

        applyLibrarySegmentTheme()
    }

    private func applyLibrarySegmentTheme() {
        let colors = DiscourseColors.current
        librarySegment.selectedSegmentTintColor = colors.accent
        librarySegment.setTitleTextAttributes([.foregroundColor: colors.primaryText], for: .normal)
        librarySegment.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
    }

    @objc func handleShortcutItem(_ item: UIApplicationShortcutItem) {
        switch item.type {
        case kVLCApplicationShortcutLastPlayed:
            handleLastPlayedShortcut()
        case kVLCApplicationShortcutLocalAudio:
            showLocalLibrary()
        case kVLCApplicationShortcutPlaylist:
            selectTab(.playlists)
        default:
            assertionFailure("unhandled shortcut")
        }
    }

    private func selectTab(_ destination: Destination) {
        tabBarController.selectedIndex = destination.rawValue
    }

    /// Opens the device audio library in the Discourses tab, optionally
    /// deep-linked to one album.
    /// The Audio Mixer's empty state asks for the library; it is the only place
    /// tracks can be added to the mixer.
    @objc private func revealLocalLibrary() {
        showLocalLibrary()
    }

    private func showLocalLibrary(pushing album: VLCMLAlbum? = nil) {
        selectTab(.discourses)
        installLibraryRoot(.local, animated: false)
        // The shortcut always lands on the library root, not on whatever album
        // list was open last time.
        discoursesNavigationController.popToRootViewController(animated: false)

        guard let album else {
            return
        }

        localLibraryViewController.loadViewIfNeeded()
        guard let albumCategory = localLibraryViewController.viewControllers
            .compactMap({ $0 as? AlbumCategoryViewController }).first else {
            return
        }
        albumCategory.pushCollectionViewController(for: album)
    }

    @objc(showTabForMedia:) func showTab(for media: VLCMLMedia) {
        // Every local library surface lives under the Discourses tab in this fork.
        selectTab(.discourses)
    }

    private func handleLastPlayedShortcut() {
        guard !KeychainCoordinator.passcodeService.hasSecret,
              let lastMedia = mediaLibraryService.lastPlayedMedia() else {
            return
        }

        let album = lastMedia.type() == .audio ? lastMedia.album : nil
        if let album = album {
            openAlbum(album)
        }

        // the queue on disk is only written when backgrounding, hence stale while anything plays
        guard !PlaybackService.sharedInstance().playerIsSetup else {
            return
        }

        let openInMiniPlayer = album != nil
        mediaLibraryService.restoreLastPlayedMediaList(onDemand: true,
                                                      openInMiniPlayer: openInMiniPlayer) {
            PlaybackService.sharedInstance().play(lastMedia, openInMiniPlayer: openInMiniPlayer)
        }
    }

    private func openAlbum(_ album: VLCMLAlbum) {
        showLocalLibrary(pushing: album)
    }
}

// MARK: - Last played quick action

extension TabBarCoordinator: MediaLibraryObserver {
    func medialibrary(_ medialibrary: MediaLibraryService, historyChangedOfType type: VLCMLHistoryType) {
        let subtitle = lastPlayedShortcutSubtitle()
        DispatchQueue.main.async {
            self.updateLastPlayedShortcutItem(subtitle: subtitle)
        }
    }

    @objc func handleDidEnterBackgroundNotification() {
        updateLastPlayedShortcutItem(subtitle: lastPlayedShortcutSubtitle())
    }

    private func lastPlayedShortcutSubtitle() -> String? {
        guard mediaLibraryService.isMediaLibrarySetup,
              !KeychainCoordinator.passcodeService.hasSecret,
              let lastMedia = mediaLibraryService.lastPlayedMedia() else {
            return nil
        }

        return lastMedia.album?.title ?? lastMedia.title
    }

    private func updateLastPlayedShortcutItem(subtitle: String?) {
        let application = UIApplication.shared
        let currentItems = application.shortcutItems ?? []
        let currentItem = currentItems.first { $0.type == kVLCApplicationShortcutLastPlayed }

        // we only ever create this item with a subtitle, so it stands in for the whole state
        guard subtitle != currentItem?.localizedSubtitle else {
            return
        }

        var shortcutItems = currentItems.filter {
            $0.type != kVLCApplicationShortcutLastPlayed
        }

        if let subtitle = subtitle {
            let item = UIApplicationShortcutItem(type: kVLCApplicationShortcutLastPlayed,
                                                 localizedTitle: NSLocalizedString("LAST_PLAYED", comment: ""),
                                                 localizedSubtitle: subtitle,
                                                 icon: UIApplicationShortcutIcon(type: .play),
                                                 userInfo: nil)
            shortcutItems.insert(item, at: 0)
        }

        application.shortcutItems = shortcutItems
    }
}

// MARK: - UITabBarControllerDelegate

extension TabBarCoordinator: UITabBarControllerDelegate {
    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        if viewController === tabBarController.selectedViewController {
            ((viewController as? UINavigationController)?.topViewController as? MediaViewController)?.scrollToTop()
        }
        return true
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        guard let index = tabBarController.viewControllers?.firstIndex(of: viewController) else {
            return
        }

        // 0 Home, 1 Discourses, 2 Search, 3 Playlists, 4 Audio Mixer.
        UserDefaults.standard.set(index, forKey: kVLCTabBarIndex)
    }
}

#if os(iOS)
@available(iOS 18.0, *)
extension TabBarCoordinator: UITabBarController.Sidebar.Delegate {
    func tabBarController(_ tabBarController: UITabBarController, sidebarVisibilityWillChange sidebar: UITabBarController.Sidebar, animator: any UITabBarController.Sidebar.Animating) {
        // The tab set is fixed now, so only the edit toolbar and the mini player
        // need to know that the sidebar appeared or disappeared.
        NotificationCenter.default.post(name: NSNotification.Name("sidebarVisibilityChanged"), object: nil)
    }
}
#endif
