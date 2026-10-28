/*****************************************************************************
 * DiscourseDetailViewController.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * A discourse and its tracks. Tapping a track queues the whole discourse from
 * that position; "Play all" queues it from the start; the long-press menu can
 * play next or append to the current queue. The row that is currently playing is
 * marked from the identity the media factory attached to the player item.
 *****************************************************************************/

import UIKit

final class DiscourseDetailViewController: UIViewController {
    private let discourse: Discourse
    private let client: DiscourseAPIClient
    private let playback: DiscoursePlayback
    private let playbackStore: DiscoursePlaybackStore
    private let likesStore: DiscourseLikesStore
    private let highlightedAudioID: String?

    private let headerView = DiscourseDetailHeaderView()
    private var tableView: UITableView!
    private let refreshControl = UIRefreshControl()
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    private var stateView: DiscourseEmptyStateView?

    private var tracks: [DiscourseAudio] = []
    private var hasLoaded = false
    private var playingAudioID: String?
    private var requestToken = 0
    private var downloadMenuButton: UIBarButtonItem?
    private var playlistActions: EditActions?
    private var hasScrolledToHighlightedTrack = false

    init(discourse: Discourse,
         highlightedAudioID: String? = nil,
         client: DiscourseAPIClient = .shared,
         playback: DiscoursePlayback = .shared,
         playbackStore: DiscoursePlaybackStore = .shared,
         likesStore: DiscourseLikesStore = .shared) {
        self.discourse = discourse
        self.highlightedAudioID = highlightedAudioID
        self.client = client
        self.playback = playback
        self.playbackStore = playbackStore
        self.likesStore = likesStore
        super.init(nibName: nil, bundle: nil)
        title = discourse.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = DiscourseColors.current.appBackground
        navigationItem.largeTitleDisplayMode = .never

        setupTableView()
        setupLoadingIndicator()
        headerView.configure(with: discourse, like: discourseLikeState())
        headerView.setPlayAllEnabled(false)
        headerView.playAllButton.addTarget(self, action: #selector(playAll), for: .touchUpInside)
        headerView.likeControl.addTarget(self, action: #selector(toggleDiscourseLike), for: .touchUpInside)
        tableView.tableHeaderView = headerView
        setupDownloadMenu()
        recordHistory()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateTheme),
                                               name: .VLCThemeDidChangeNotification,
                                               object: nil)
        addPlaybackObservers()
        addMiniPlayerObservers()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(progressDidChange(_:)),
                                               name: .discoursePlaybackProgressDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(likesDidChange),
                                               name: .discourseLikesDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(downloadsDidChange),
                                               name: .discourseDownloadsDidChange,
                                               object: nil)
        updateTheme()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updatePlayingState()
        updateMiniPlayerInset()
        if !hasLoaded {
            loadTracks(forceRefresh: false)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scrollToHighlightedTrackIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sizeHeaderIfNeeded()
    }

    // MARK: - History

    /// Opening a discourse counts as a play for the recently-played list
    /// (AGENTS §6.5); the playback-history setting gates it like track history.
    private func recordHistory() {
        guard DiscoursePlaybackSettings.isHistoryEnabled else {
            return
        }
        DiscourseHistoryStore.shared.record(discourse: discourse)
    }

    // MARK: - Setup

    private func setupTableView() {
        tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64
        tableView.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 24, right: 0)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.accessibilityIdentifier = "discourseTracks"
        tableView.register(DiscourseTrackCell.self,
                           forCellReuseIdentifier: DiscourseTrackCell.reuseIdentifier)

        refreshControl.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        tableView.refreshControl = refreshControl

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
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

    /// The mini player floats above the tab bar, so the last rows scroll clear
    /// of it instead of hiding underneath.
    @objc private func updateMiniPlayerInset() {
        let visible = PlaybackService.sharedInstance().playerDisplayController.isMiniPlayerVisible
        tableView.contentInset.bottom = 24 + (visible ? CGFloat(AudioMiniPlayer.height) : 0)
            + discourseFloatingTabBarInset
        tableView.verticalScrollIndicatorInsets.bottom = tableView.contentInset.bottom
    }

    private func sizeHeaderIfNeeded() {
        let header = tableView.tableHeaderView
        let width = tableView.bounds.width
        guard let header, width > 0 else {
            return
        }

        let target = CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
        let height = header.systemLayoutSizeFitting(target,
                                                    withHorizontalFittingPriority: .required,
                                                    verticalFittingPriority: .fittingSizeLevel).height
        guard abs(header.frame.height - height) > 0.5 || abs(header.frame.width - width) > 0.5 else {
            return
        }
        header.frame = CGRect(x: 0, y: 0, width: width, height: height)
        tableView.tableHeaderView = header
    }

    // MARK: - Loading

    @objc private func handleRefresh() {
        loadTracks(forceRefresh: true)
    }

    private func loadTracks(forceRefresh: Bool) {
        requestToken += 1
        let token = requestToken

        if tracks.isEmpty {
            showLoading()
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let fetched = try await self.client.discourseTracks(discourseID: self.discourse.id,
                                                                    forceRefresh: forceRefresh)
                guard token == self.requestToken else { return }

                self.tracks = fetched.sorted(by: Self.trackOrder)
                self.hasLoaded = true
                self.updateDownloadMenu()
                // Durations drive the progress rings even before a track plays.
                self.playbackStore.register(self.tracks)
                self.seedLikeCounts(self.tracks)
                self.refreshControl.endRefreshing()
                self.headerView.setPlayAllEnabled(!self.tracks.isEmpty)
                self.tableView.reloadData()
                self.updatePlayingState()

                if self.tracks.isEmpty {
                    self.showEmptyState()
                } else {
                    self.showContent()
                    self.scrollToHighlightedTrackIfNeeded()
                }
            } catch {
                guard token == self.requestToken else { return }
                self.refreshControl.endRefreshing()
                guard !Self.isCancellation(error) else { return }

                if self.tracks.isEmpty {
                    self.showErrorState()
                } else {
                    self.showContent()
                }
            }
        }
    }

    private static func trackOrder(_ lhs: DiscourseAudio, _ rhs: DiscourseAudio) -> Bool {
        let left = lhs.trackNumber ?? Int.max
        let right = rhs.trackNumber ?? Int.max
        if left != right {
            return left < right
        }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private static func isCancellation(_ error: Error) -> Bool {
        guard let apiError = error as? DiscourseAPIError else {
            return false
        }
        if case .cancelled = apiError {
            return true
        }
        return false
    }

    /// A deep link to a track scrolls the loaded list to that row once. The
    /// flag prevents a refresh or a later reload from moving the user again.
    private func scrollToHighlightedTrackIfNeeded() {
        guard !hasScrolledToHighlightedTrack,
              let highlightedAudioID,
              let row = tracks.firstIndex(where: { $0.id == highlightedAudioID }) else {
            return
        }
        hasScrolledToHighlightedTrack = true
        let indexPath = IndexPath(row: row, section: 0)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.tableView.layoutIfNeeded()
            self.tableView.scrollToRow(at: indexPath, at: .middle, animated: true)
        }
    }

    // MARK: - Playback

    @objc private func playAll() {
        playTrack(at: 0)
    }

    private func playTrack(at index: Int) {
        guard tracks.indices.contains(index) else {
            return
        }
        _ = playback.play(tracks: tracks, discourse: discourse, startingAt: index)
    }

    @objc private func playbackDidChange() {
        updatePlayingState()
    }

    // MARK: - Likes

    private func discourseLikeState() -> DiscourseLikeState {
        return DiscourseLikeState.resolve(target: .discourse(discourse.id),
                                          payloadLikes: discourse.totalLikes,
                                          store: likesStore)
    }

    private func likeState(for track: DiscourseAudio) -> DiscourseLikeState {
        return DiscourseLikeState.resolve(target: .audio(track.id),
                                          payloadLikes: track.totalLikes,
                                          store: likesStore)
    }

    /// Records the counts that arrived with the payload; a pending toggle keeps
    /// its optimistic count.
    private func seedLikeCounts(_ tracks: [DiscourseAudio]) {
        for track in tracks {
            likesStore.updateCount(track.totalLikes, for: .audio(track.id))
        }
        likesStore.updateCount(discourse.totalLikes, for: .discourse(discourse.id))
    }

    /// Refreshes the header and the visible rows after a toggle settles.
    @objc private func likesDidChange() {
        headerView.configure(with: discourse, like: discourseLikeState())
        headerView.setPlayAllEnabled(!tracks.isEmpty)
        for indexPath in tableView.indexPathsForVisibleRows ?? [] {
            guard tracks.indices.contains(indexPath.row),
                  let cell = tableView.cellForRow(at: indexPath) as? DiscourseTrackCell else {
                continue
            }
            configure(cell, at: indexPath.row)
        }
    }

    @objc private func toggleDiscourseLike() {
        DiscourseLikeActions.toggleDiscourse(discourse, from: self, store: likesStore)
    }

    // MARK: - Downloads

    private func setupDownloadMenu() {
        let button = UIBarButtonItem(image: UIImage(systemName: "arrow.down.circle"),
                                     style: .plain,
                                     target: nil,
                                     action: nil)
        button.accessibilityLabel = NSLocalizedString("DISCOURSE_DOWNLOADS_MENU",
                                                      comment: "Accessibility label of the downloads menu in the discourse screen")
        button.accessibilityIdentifier = "discourseDownloadsMenu"
        navigationItem.rightBarButtonItem = button
        downloadMenuButton = button
        updateDownloadMenu()
    }

    /// Rebuilt whenever tracks load or a download changes, so the menu only
    /// offers actions that can do something.
    private func updateDownloadMenu() {
        guard let button = downloadMenuButton else {
            return
        }
        let downloaded = DiscourseDownloadStore.shared.downloadedCount(forDiscourse: discourse.id)
        let active = DiscourseDownloadManager.shared.activeCount(forDiscourse: discourse.id)

        var actions: [UIMenuElement] = []
        var downloadAttributes: UIAction.Attributes = []
        if tracks.isEmpty || downloaded >= tracks.count {
            downloadAttributes.insert(.disabled)
        }
        actions.append(UIAction(title: NSLocalizedString("DISCOURSE_DOWNLOAD_ALL_MENU",
                                                         comment: "Download every track of this discourse"),
                                image: UIImage(systemName: "arrow.down.circle"),
                                attributes: downloadAttributes) { [weak self] _ in
            self?.downloadAllTracks()
        })

        if active > 0 {
            actions.append(UIAction(title: NSLocalizedString("DISCOURSE_DOWNLOAD_CANCEL_ALL_MENU",
                                                             comment: "Cancel every running download of this discourse"),
                                    image: UIImage(systemName: "xmark.circle")) { [weak self] _ in
                guard let self else { return }
                DiscourseDownloadManager.shared.cancelAll(discourseID: self.discourse.id)
            })
        }

        if downloaded > 0 {
            actions.append(UIAction(title: NSLocalizedString("DISCOURSE_DOWNLOAD_REMOVE_ALL_MENU",
                                                             comment: "Delete every downloaded track of this discourse"),
                                    image: UIImage(systemName: "trash"),
                                    attributes: .destructive) { [weak self] _ in
                guard let self else { return }
                DiscourseDownloadActions.confirmRemoveAll(in: self,
                                                          discourseID: self.discourse.id,
                                                          discourseTitle: self.discourse.title)
            })
        }

        button.menu = UIMenu(title: "", children: actions)
        button.isEnabled = !tracks.isEmpty
    }

    private func downloadAllTracks() {
        DiscourseDownloadManager.shared.downloadAll(tracks: tracks,
                                                    discourseID: discourse.id)
    }

    /// Refreshes the menu and the visible download arrows in place.
    @objc private func downloadsDidChange() {
        updateDownloadMenu()
        for indexPath in tableView.indexPathsForVisibleRows ?? [] {
            guard tracks.indices.contains(indexPath.row),
                  let cell = tableView.cellForRow(at: indexPath) as? DiscourseTrackCell else {
                continue
            }
            configure(cell, at: indexPath.row)
        }
    }

    /// The tracker saves a position or completes a track: refresh just that row
    /// so the ring follows playback without reloading the table.
    @objc private func progressDidChange(_ notification: Notification) {
        guard let audioID = notification.userInfo?[DiscoursePlaybackStore.audioIDKey] as? String,
              let row = tracks.firstIndex(where: { $0.id == audioID }) else {
            tableView.reloadData()
            return
        }
        let indexPath = IndexPath(row: row, section: 0)
        if tableView.indexPathsForVisibleRows?.contains(indexPath) == true {
            tableView.reloadRows(at: [indexPath], with: .none)
        }
    }

    private func updatePlayingState() {
        let audioID = playback.currentIdentity()?.audioID
        guard audioID != playingAudioID else {
            return
        }
        playingAudioID = audioID
        tableView.reloadData()
    }

    // MARK: - States

    private func showLoading() {
        removeStateView()
        tableView.isHidden = true
        loadingIndicator.startAnimating()
    }

    private func showContent() {
        removeStateView()
        loadingIndicator.stopAnimating()
        tableView.isHidden = false
    }

    private func showEmptyState() {
        showState(symbolName: "music.note.list",
                  heading: NSLocalizedString("DISCOURSE_DETAIL_EMPTY_TITLE",
                                            comment: "Detail screen heading when a discourse has no tracks"),
                  message: NSLocalizedString("DISCOURSE_DETAIL_EMPTY_MESSAGE",
                                            comment: "Detail screen message when a discourse has no tracks"),
                  actionTitle: NSLocalizedString("DISCOURSE_CATALOGUE_RELOAD",
                                                 comment: "Reload the tracks")) { [weak self] in
            self?.loadTracks(forceRefresh: true)
        }
    }

    private func showErrorState() {
        showState(symbolName: "wifi.exclamationmark",
                  heading: NSLocalizedString("DISCOURSE_DETAIL_ERROR_TITLE",
                                            comment: "Detail screen heading when the tracks fail to load"),
                  message: DiscourseErrorCopy.serverFailure,
                  actionTitle: NSLocalizedString("DISCOURSE_CATALOGUE_RETRY",
                                                 comment: "Retry loading the tracks")) { [weak self] in
            self?.loadTracks(forceRefresh: true)
        }
    }

    private func showState(symbolName: String,
                           heading: String,
                           message: String,
                           actionTitle: String,
                           action: (() -> Void)?) {
        removeStateView()
        loadingIndicator.stopAnimating()
        tableView.isHidden = true

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
        self.stateView = stateView
    }

    private func removeStateView() {
        stateView?.removeFromSuperview()
        stateView = nil
    }

    // MARK: - Theme

    @objc private func updateTheme() {
        let colors = DiscourseColors.current
        view.backgroundColor = colors.appBackground
        loadingIndicator.color = colors.accent
        refreshControl.tintColor = colors.accent
        headerView.updateTheme()
        stateView?.updateTheme()
        tableView.reloadData()
    }
}

// MARK: - UITableViewDataSource

extension DiscourseDetailViewController: UITableViewDataSource {
    private func configure(_ cell: DiscourseTrackCell, at row: Int) {
        guard tracks.indices.contains(row) else {
            return
        }
        let track = tracks[row]
        cell.configure(with: track,
                       position: track.trackNumber ?? row + 1,
                       fraction: playbackStore.fraction(audioID: track.id),
                       isCompleted: playbackStore.isCompleted(audioID: track.id),
                       isPlaying: track.id == playingAudioID,
                       like: likeState(for: track),
                       download: DiscourseDownloadManager.shared.state(for: track.id))
        cell.onOpen = { [weak self] in
            self?.playTrack(at: row)
        }
        cell.onToggleLike = { [weak self] in
            DiscourseLikeActions.toggleAudio(track, from: self)
        }
        cell.onToggleDownload = {
            DiscourseDownloadActions.toggle(track, discourseID: track.discourseID)
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return tracks.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: DiscourseTrackCell.reuseIdentifier,
                                                 for: indexPath)
        guard let trackCell = cell as? DiscourseTrackCell, tracks.indices.contains(indexPath.row) else {
            return cell
        }

        configure(trackCell, at: indexPath.row)
        return trackCell
    }
}

// MARK: - UITableViewDelegate

extension DiscourseDetailViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard tracks.indices.contains(indexPath.row),
              let url = tracks[indexPath.row].audioURL else { return nil }
        let track = tracks[indexPath.row]
        let action = UIContextualAction(style: .normal,
                                       title: NSLocalizedString("ADD_TO_PLAYLIST", comment: "")) { [weak self] _, _, completion in
            guard let self else { completion(false); return }
            let library = VLCAppCoordinator.sharedInstance().mediaLibraryService
            guard let media = library.fetchOrCreateMedia(with: url) else {
                VLCAlertViewController.alertViewManager(title: NSLocalizedString("ERROR_PLAYLIST_CREATION", comment: ""),
                                                        viewController: self)
                completion(false)
                return
            }
            DiscourseMediaIdentityStore.shared.record(url: url,
                                                      identity: DiscourseMediaFactory.identity(for: track, discourse: self.discourse))
            let actions = EditActions(model: PlaylistModel(medialibrary: library), mediaLibraryService: library)
            actions.objects = [media]
            self.playlistActions = actions
            completion(true)
            actions.addToPlaylist()
        }
        action.image = UIImage(systemName: "text.badge.plus")
        action.backgroundColor = DiscourseColors.current.accent
        let configuration = UISwipeActionsConfiguration(actions: [action])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        playTrack(at: indexPath.row)
    }

    func tableView(_ tableView: UITableView,
                   contextMenuConfigurationForRowAt indexPath: IndexPath,
                   point: CGPoint) -> UIContextMenuConfiguration? {
        guard tracks.indices.contains(indexPath.row) else {
            return nil
        }

        let track = tracks[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }

            let play = UIAction(title: NSLocalizedString("DISCOURSE_TRACK_PLAY",
                                                         comment: "Play a track now"),
                                image: UIImage(systemName: "play.fill")) { _ in
                self.playTrack(at: indexPath.row)
            }
            let playNext = UIAction(title: NSLocalizedString("DISCOURSE_TRACK_PLAY_NEXT",
                                                             comment: "Insert a track after the current one"),
                                    image: UIImage(systemName: "text.line.first.and.arrowtriangle.forward")) { _ in
                self.playback.playNext(track, discourse: self.discourse)
            }
            let append = UIAction(title: NSLocalizedString("DISCOURSE_TRACK_ADD_TO_QUEUE",
                                                           comment: "Append a track to the queue"),
                                  image: UIImage(systemName: "text.line.last.and.arrowtriangle.forward")) { _ in
                self.playback.appendToQueue(track, discourse: self.discourse)
            }
            var children: [UIMenuElement] = [play, playNext, append]
            if let download = DiscourseDownloadActions.menuAction(for: track,
                                                                  discourseID: self.discourse.id) {
                children.append(download)
            }
            return UIMenu(children: children)
        }
    }
}
