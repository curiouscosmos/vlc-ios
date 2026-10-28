/*****************************************************************************
 * DiscourseHomeViewController.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * The Home tab: recently played discourses and tracks from the local history
 * stores, then this week's top discourses and tracks from the weekly stats
 * cache. Sections are hidden while empty and the whole screen falls back to an
 * empty or error state. Pull-to-refresh forces a stats reload; the history is
 * read synchronously from UserDefaults and refreshed whenever a store changes.
 *****************************************************************************/

import UIKit

final class DiscourseHomeViewController: UIViewController {
    private let statsCache: DiscourseStatsCache
    private let history: DiscourseHistoryStore
    private let playback: DiscoursePlayback
    private let likesStore: DiscourseLikesStore
    private let mediaLibrary: MediaLibraryService?

    private var collectionView: UICollectionView!
    private let refreshControl = UIRefreshControl()
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    private var stateView: DiscourseEmptyStateView?

    private var sections: [DiscourseHomeSection] = []
    private var topDiscourses: [Discourse] = []
    private var topTracks: [DiscourseAudio] = []
    private var hasLoadedStats = false
    private var isLoadingStats = false
    private var statsFailed = false
    /// Bumped for every stats request so a slow answer cannot overwrite a newer
    /// one (pull-to-refresh racing the first load).
    private var requestToken = 0
    private var playingAudioID: String?
    private var playingLocalURL: URL?
    private var localTracks: [DiscourseLocalTrack] = []

    init(statsCache: DiscourseStatsCache = .shared,
         history: DiscourseHistoryStore = .shared,
         playback: DiscoursePlayback = .shared,
         likesStore: DiscourseLikesStore = .shared,
         mediaLibrary: MediaLibraryService? = nil) {
        self.statsCache = statsCache
        self.history = history
        self.playback = playback
        self.likesStore = likesStore
        self.mediaLibrary = mediaLibrary
        super.init(nibName: nil, bundle: nil)
        // The tab carries the name; the screen shows its content without a
        // navigation title.
        title = nil
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = DiscourseColors.current.appBackground
        navigationItem.largeTitleDisplayMode = .never
        // The logo is decorative; the app menu lives on the right.
        navigationItem.leftBarButtonItem = AppLogoBarButtonItem()
        navigationItem.rightBarButtonItem = AppMenuBarButtonItem(presenter: self, style: .dropdown)

        setupCollectionView()
        setupLoadingIndicator()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateTheme),
                                               name: .VLCThemeDidChangeNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(historyDidChange),
                                               name: .discourseHistoryDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(likesDidChange),
                                               name: .discourseLikesDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(downloadsDidChange),
                                               name: .discourseDownloadsDidChange,
                                               object: nil)
        addPlaybackObservers()
        addMiniPlayerObservers()

        reloadHistory()
        loadStats(forceRefresh: false)
        updateTheme()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadHistory()
        updatePlayingState()
        updateMiniPlayerInset()
        if !hasLoadedStats && !isLoadingStats {
            loadStats(forceRefresh: false)
        }
    }

    // MARK: - Setup

    private func setupCollectionView() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 24, right: 0)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.accessibilityIdentifier = "discourseHome"
        collectionView.register(DiscourseCardCell.self,
                                forCellWithReuseIdentifier: DiscourseCardCell.reuseIdentifier)
        collectionView.register(DiscourseHomeTrackCell.self,
                                forCellWithReuseIdentifier: DiscourseHomeTrackCell.reuseIdentifier)
        collectionView.register(DiscourseHomeLoadingCell.self,
                                forCellWithReuseIdentifier: DiscourseHomeLoadingCell.reuseIdentifier)
        collectionView.register(DiscourseHomeSectionHeaderView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: DiscourseHomeSectionHeaderView.reuseIdentifier)

        refreshControl.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        collectionView.refreshControl = refreshControl

        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupLoadingIndicator() {
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.hidesWhenStopped = true
        view.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor)
        ])
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        return UICollectionViewCompositionalLayout { [weak self] index, _ in
            guard let self, self.sections.indices.contains(index) else {
                return nil
            }
            return self.layoutSection(for: self.sections[index].kind)
        }
    }

    private func layoutSection(for kind: DiscourseHomeSectionKind) -> NSCollectionLayoutSection {
        let header = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1),
                                               heightDimension: .estimated(35)),
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top)

        if kind.isCarousel {
            let itemSize = NSCollectionLayoutSize(widthDimension: .absolute(160),
                                                  heightDimension: .estimated(230))
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: itemSize, subitems: [item])

            let section = NSCollectionLayoutSection(group: group)
            section.orthogonalScrollingBehavior = .continuous
            section.interGroupSpacing = 12
            section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 16, trailing: 16)
            section.boundarySupplementaryItems = [header]
            return section
        }

        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1),
                                              heightDimension: .estimated(74))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let group = NSCollectionLayoutGroup.vertical(layoutSize: itemSize, subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 6
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 16, trailing: 0)
        section.boundarySupplementaryItems = [header]
        return section
    }

    private func addPlaybackObservers() {
        let names = [VLCPlaybackServicePlaybackDidStart,
                     VLCPlaybackServicePlaybackDidMoveOnToNextItem,
                     VLCPlaybackServicePlaybackDidStop,
                     VLCPlaybackServicePlaybackDidFail]
        for name in names {
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(playbackDidChange),
                                                   name: Notification.Name(name),
                                                   object: nil)
        }
    }

    private func addMiniPlayerObservers() {
        let names = [VLCPlayerDisplayControllerDisplayMiniPlayer, VLCPlayerDisplayControllerHideMiniPlayer]
        for name in names {
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(updateMiniPlayerInset),
                                                   name: NSNotification.Name(rawValue: name),
                                                   object: nil)
        }
    }

    @objc private func updateMiniPlayerInset() {
        let visible = PlaybackService.sharedInstance().playerDisplayController.isMiniPlayerVisible
        collectionView.contentInset.bottom = 24 + (visible ? CGFloat(AudioMiniPlayer.height) : 0)
            + discourseFloatingTabBarInset
        collectionView.verticalScrollIndicatorInsets.bottom = collectionView.contentInset.bottom
    }

    // MARK: - Content

    private func reloadHistory() {
        let historyEnabled = DiscoursePlaybackSettings.isHistoryEnabled
        localTracks = historyEnabled ? localHistoryTracks() : []
        applySections(DiscourseHomeContent.sections(recentDiscourses: history.recentlyPlayedDiscourses,
                                                    recentTracks: historyEnabled ? history.recentlyPlayedAudios : [],
                                                    topDiscourses: topDiscourses,
                                                    topTracks: topTracks,
                                                    localTracks: localTracks,
                                                    historyEnabled: historyEnabled,
                                                    topListsLoading: isLoadingStats))
    }

    /// The device library's own playback history (AGENTS section 6.1). The
    /// library records a play itself, so Home only has to display it.
    private func localHistoryTracks() -> [DiscourseLocalTrack] {
        guard let history = mediaLibrary?.medialib.audioHistory() else {
            return []
        }
        return DiscourseLocalTrack.list(from: history)
    }

    private func applySections(_ newSections: [DiscourseHomeSection]) {
        sections = newSections
        seedLikeCounts(newSections)
        collectionView.reloadData()
        collectionView.collectionViewLayout.invalidateLayout()
        renderState()
    }

    /// Records the counts that arrived with the payloads; a pending toggle keeps
    /// its optimistic count.
    private func seedLikeCounts(_ sections: [DiscourseHomeSection]) {
        for section in sections {
            for item in section.items {
                switch item {
                case .discourse(let discourse):
                    likesStore.updateCount(discourse.totalLikes, for: .discourse(discourse.id))
                case .track(let track):
                    likesStore.updateCount(track.totalLikes, for: .audio(track.id))
                case .localTrack, .loading:
                    // Library tracks carry no discourse like state, and the
                    // loading placeholder has no payload.
                    break
                }
            }
        }
    }

    /// Updates the rendered hearts in place after a toggle settles.
    @objc private func likesDidChange() {
        for cell in collectionView.visibleCells {
            guard let indexPath = collectionView.indexPath(for: cell) else {
                continue
            }
            reconfigure(cell, at: indexPath)
        }
    }

    /// Updates the rendered download arrows in place.
    @objc private func downloadsDidChange() {
        for cell in collectionView.visibleCells {
            guard let indexPath = collectionView.indexPath(for: cell) else {
                continue
            }
            reconfigure(cell, at: indexPath)
        }
    }

    private func reconfigure(_ cell: UICollectionViewCell, at indexPath: IndexPath) {
        guard sections.indices.contains(indexPath.section),
              sections[indexPath.section].items.indices.contains(indexPath.item) else {
            return
        }
        let item = sections[indexPath.section].items[indexPath.item]
        switch (item, cell) {
        case (.discourse(let discourse), let card as DiscourseCardCell):
            card.configure(with: discourse,
                           like: likeState(for: discourse),
                           downloads: downloadState(for: discourse))
        case (.track(let track), let row as DiscourseHomeTrackCell):
            row.configure(with: track,
                          isPlaying: track.id == playingAudioID,
                          like: likeState(for: track),
                          download: downloadState(for: track))
        case (.localTrack(let track), let row as DiscourseHomeTrackCell):
            row.configure(with: track, isPlaying: track.url == playingLocalURL)
        case (.loading, _):
            break
        default:
            break
        }
    }

    private func downloadState(for discourse: Discourse) -> DiscourseDownloadSummary {
        return DiscourseDownloadSummary.resolve(discourseID: discourse.id,
                                                totalTracks: discourse.totalTracks)
    }

    private func downloadState(for track: DiscourseAudio) -> DiscourseDownloadState {
        return DiscourseDownloadManager.shared.state(for: track.id)
    }

    private func likeState(for discourse: Discourse) -> DiscourseLikeState {
        return DiscourseLikeState.resolve(target: .discourse(discourse.id),
                                          payloadLikes: discourse.totalLikes,
                                          store: likesStore)
    }

    private func likeState(for track: DiscourseAudio) -> DiscourseLikeState {
        return DiscourseLikeState.resolve(target: .audio(track.id),
                                          payloadLikes: track.totalLikes,
                                          store: likesStore)
    }

    private func loadStats(forceRefresh: Bool) {
        guard !isLoadingStats else {
            refreshControl.endRefreshing()
            return
        }

        isLoadingStats = true
        requestToken += 1
        let token = requestToken
        // Rebuild immediately so the weekly sections show their placeholders
        // while history is already on screen.
        reloadHistory()

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                async let discoursPage = self.statsCache.discourses(window: .last7Days,
                                                                    forceRefresh: forceRefresh)
                async let audioPage = self.statsCache.audios(window: .last7Days,
                                                             forceRefresh: forceRefresh)
                let (topDiscourses, topTracks) = try await (discoursPage, audioPage)

                guard token == self.requestToken else { return }
                self.isLoadingStats = false
                self.hasLoadedStats = true
                self.statsFailed = false
                self.topDiscourses = topDiscourses
                self.topTracks = topTracks
                self.reloadHistory()
                self.refreshControl.endRefreshing()
            } catch {
                guard token == self.requestToken else { return }
                self.isLoadingStats = false
                self.hasLoadedStats = true
                self.statsFailed = true
                self.reloadHistory()
                self.refreshControl.endRefreshing()
            }
        }
    }

    // MARK: - States

    private func renderState() {
        if !sections.isEmpty {
            collectionView.isHidden = false
            removeStateView()
            loadingIndicator.stopAnimating()
            return
        }

        collectionView.isHidden = true

        if isLoadingStats || !hasLoadedStats {
            removeStateView()
            loadingIndicator.startAnimating()
            return
        }

        loadingIndicator.stopAnimating()

        if statsFailed {
            showState(symbolName: "wifi.exclamationmark",
                      heading: NSLocalizedString("HOME_ERROR_TITLE",
                                                comment: "Home heading when the top lists cannot be loaded"),
                      message: DiscourseErrorCopy.serverFailure,
                      actionTitle: NSLocalizedString("DISCOURSE_CATALOGUE_RETRY",
                                                    comment: "Retry loading the Home screen"),
                      action: { [weak self] in
                          self?.loadStats(forceRefresh: true)
                      })
        } else {
            showState(symbolName: "house",
                      heading: NSLocalizedString("HOME_EMPTY_TITLE",
                                                comment: "Empty state heading on the Home tab"),
                      message: NSLocalizedString("HOME_EMPTY_MESSAGE",
                                                comment: "Empty state message on the Home tab"),
                      actionTitle: nil,
                      action: nil)
        }
    }

    private func showState(symbolName: String,
                           heading: String,
                           message: String,
                           actionTitle: String?,
                           action: (() -> Void)?) {
        removeStateView()

        let stateView = DiscourseEmptyStateView(symbolName: symbolName,
                                                heading: heading,
                                                message: message,
                                                actionTitle: actionTitle)
        stateView.actionHandler = action
        stateView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stateView)

        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stateView.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
            stateView.centerYAnchor.constraint(equalTo: safeArea.centerYAnchor),
            stateView.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor, constant: 24),
            stateView.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor, constant: -24),
            stateView.widthAnchor.constraint(lessThanOrEqualToConstant: 480)
        ])
        stateView.updateTheme()
        self.stateView = stateView
    }

    private func removeStateView() {
        stateView?.removeFromSuperview()
        stateView = nil
    }

    // MARK: - Actions

    @objc private func handleRefresh() {
        reloadHistory()
        loadStats(forceRefresh: true)
    }

    @objc private func historyDidChange() {
        reloadHistory()
    }

    @objc private func playbackDidChange() {
        updatePlayingState()
    }

    private func updatePlayingState() {
        // `currentlyPlayingMedia` survives a stop, so only a player that is
        // actually playing marks a row.
        let service = PlaybackService.sharedInstance()
        let isPlaying = service.isPlaying
        let audioID = isPlaying ? playback.currentIdentity()?.audioID : nil
        let localURL = isPlaying ? service.currentlyPlayingMedia?.url : nil
        guard audioID != playingAudioID || localURL != playingLocalURL else {
            return
        }
        playingAudioID = audioID
        playingLocalURL = localURL
        if !sections.isEmpty {
            collectionView.reloadData()
        }
    }

    // MARK: - Theme

    @objc private func updateTheme() {
        let colors = DiscourseColors.current
        view.backgroundColor = colors.appBackground
        collectionView.backgroundColor = .clear
        loadingIndicator.color = colors.accent
        refreshControl.tintColor = colors.accent
        stateView?.updateTheme()
        collectionView.reloadData()
    }
}

// MARK: - UICollectionViewDataSource

extension DiscourseHomeViewController: UICollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return sections.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        guard sections.indices.contains(section) else {
            return 0
        }
        return sections[section].items.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard sections.indices.contains(indexPath.section),
              sections[indexPath.section].items.indices.contains(indexPath.item) else {
            return UICollectionViewCell()
        }

        let item = sections[indexPath.section].items[indexPath.item]
        switch item {
        case .discourse(let discourse):
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: DiscourseCardCell.reuseIdentifier,
                                                          for: indexPath)
            guard let card = cell as? DiscourseCardCell else {
                return cell
            }
            card.configure(with: discourse,
                           like: likeState(for: discourse),
                           downloads: downloadState(for: discourse))
            card.onOpen = { [weak self] in
                self?.open(item)
            }
            card.onToggleLike = { [weak self] in
                DiscourseLikeActions.toggleDiscourse(discourse, from: self)
            }
            return card
        case .track(let track):
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: DiscourseHomeTrackCell.reuseIdentifier,
                                                          for: indexPath)
            guard let row = cell as? DiscourseHomeTrackCell else {
                return cell
            }
            row.configure(with: track,
                          isPlaying: track.id == playingAudioID,
                          like: likeState(for: track),
                          download: downloadState(for: track))
            row.onOpen = { [weak self] in
                self?.open(item)
            }
            row.onToggleLike = { [weak self] in
                DiscourseLikeActions.toggleAudio(track, from: self)
            }
            row.onToggleDownload = {
                DiscourseDownloadActions.toggle(track)
            }
            return row
        case .localTrack(let track):
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: DiscourseHomeTrackCell.reuseIdentifier,
                                                          for: indexPath)
            guard let row = cell as? DiscourseHomeTrackCell else {
                return cell
            }
            row.configure(with: track, isPlaying: track.url == playingLocalURL)
            row.onOpen = { [weak self] in
                self?.open(item)
            }
            return row
        case .loading:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: DiscourseHomeLoadingCell.reuseIdentifier,
                                                          for: indexPath)
            guard let loadingCell = cell as? DiscourseHomeLoadingCell else {
                return cell
            }
            loadingCell.configure()
            return loadingCell
        }
    }

    func collectionView(_ collectionView: UICollectionView,
                        viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        guard kind == UICollectionView.elementKindSectionHeader else {
            return UICollectionReusableView()
        }

        let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: DiscourseHomeSectionHeaderView.reuseIdentifier,
            for: indexPath)
        if let header = header as? DiscourseHomeSectionHeaderView,
           sections.indices.contains(indexPath.section) {
            header.configure(title: sections[indexPath.section].kind.title)
        }
        return header
    }
}

// MARK: - UICollectionViewDelegate

extension DiscourseHomeViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)

        guard sections.indices.contains(indexPath.section),
              sections[indexPath.section].items.indices.contains(indexPath.item) else {
            return
        }

        open(sections[indexPath.section].items[indexPath.item])
    }

    private func open(_ item: DiscourseHomeItem) {
        switch item {
        case .discourse(let discourse):
            let detail = DiscourseDetailViewController(discourse: discourse,
                                                       likesStore: likesStore)
            navigationController?.pushViewController(detail, animated: true)
        case .track(let track):
            playback.play(track: track, discourse: nil)
        case .localTrack(let track):
            guard let media = track.media else {
                return
            }
            // The library's own entry point, so metadata, history and the
            // mini player behave exactly as when the file is played from
            // the local library.
            PlaybackService.sharedInstance().playMedia(at: 0, fromCollection: [media])
        case .loading:
            break
        }
    }
}

private final class DiscourseHomeLoadingCell: UICollectionViewCell {
    static let reuseIdentifier = "DiscourseHomeLoadingCell"

    private let spinner = UIActivityIndicatorView(style: .medium)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = false
        contentView.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        spinner.color = DiscourseColors.current.accent
        spinner.startAnimating()
        isAccessibilityElement = true
        accessibilityLabel = NSLocalizedString("HOME_LOADING_TOP_LISTS",
                                                comment: "Home top lists loading indicator")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        spinner.startAnimating()
    }
}
