/*****************************************************************************
 * DiscourseSearchViewController.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * Search over the remote catalogue only (never the device library): discourses
 * and tracks, in two sections, fetched together for every query. Queries are
 * debounced, stale answers are dropped with a request token, and paging follows
 * whichever endpoint is deeper. Opening a discourse pushes the detail; tapping a
 * track starts it and lets the playback bridge append the rest of its discourse.
 *****************************************************************************/

import UIKit

final class DiscourseSearchViewController: UIViewController {
    private enum ContentState {
        case idle
        case loading
        case results
        case empty
        case error
    }

    private enum Section: Int, CaseIterable {
        case discourses
        case tracks

        var title: String {
            switch self {
            case .discourses:
                return NSLocalizedString("DISCOURSE_SEARCH_SECTION_DISCOURSES",
                                         comment: "Search results section title")
            case .tracks:
                return NSLocalizedString("DISCOURSE_SEARCH_SECTION_TRACKS",
                                         comment: "Search results section title")
            }
        }
    }

    private let client: DiscourseAPIClient
    private let playback: DiscoursePlayback
    private let likesStore: DiscourseLikesStore
    private let searchController = UISearchController(searchResultsController: nil)
    private let debounceInterval: TimeInterval = 0.35

    private var tableView: UITableView!
    private let refreshControl = UIRefreshControl()
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    private var stateView: DiscourseEmptyStateView?

    private var results = DiscourseSearchResults()
    private var query = ""
    private var contentState: ContentState = .idle
    /// Bumped for every new query so a slow answer cannot overwrite a newer one.
    private var requestToken = 0
    private var isLoading = false
    private var pendingSearch: DispatchWorkItem?
    private var playingAudioID: String?

    init(client: DiscourseAPIClient = .shared,
         playback: DiscoursePlayback = .shared,
         likesStore: DiscourseLikesStore = .shared) {
        self.client = client
        self.playback = playback
        self.likesStore = likesStore
        super.init(nibName: nil, bundle: nil)
        title = NSLocalizedString("SEARCH", comment: "Search tab title")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = DiscourseColors.current.appBackground
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.leftBarButtonItem = AppMenuBarButtonItem(presenter: self)

        setupSearchController()
        setupTableView()
        setupLoadingIndicator()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateTheme),
                                               name: .VLCThemeDidChangeNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(likesDidChange),
                                               name: .discourseLikesDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(likesDidChange),
                                               name: .discourseDownloadsDidChange,
                                               object: nil)
        addPlaybackObservers()
        addMiniPlayerObservers()
        render()
        updateTheme()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateMiniPlayerInset()
        updatePlayingState()
    }

    // MARK: - Setup

    private func setupSearchController() {
        searchController.searchResultsUpdater = self
        searchController.searchBar.delegate = self
        searchController.searchBar.placeholder = NSLocalizedString("DISCOURSE_SEARCH_PLACEHOLDER",
                                                                   comment: "Search field placeholder")
        searchController.searchBar.accessibilityIdentifier = "discourseSearchField"
        searchController.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    private func setupTableView() {
        tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 76
        tableView.sectionHeaderHeight = UIFont.preferredFont(forTextStyle: .headline).lineHeight + 16
        tableView.contentInset = UIEdgeInsets(top: 4, left: 0, bottom: 24, right: 0)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.accessibilityIdentifier = "discourseSearchResults"
        tableView.register(DiscourseSearchCell.self,
                           forCellReuseIdentifier: DiscourseSearchCell.reuseIdentifier)

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

    @objc private func updateMiniPlayerInset() {
        let visible = PlaybackService.sharedInstance().playerDisplayController.isMiniPlayerVisible
        tableView.contentInset.bottom = 24 + (visible ? CGFloat(AudioMiniPlayer.height) : 0)
            + discourseFloatingTabBarInset
        tableView.verticalScrollIndicatorInsets.bottom = tableView.contentInset.bottom
    }

    // MARK: - Searching

    private func scheduleSearch(for text: String) {
        pendingSearch?.cancel()
        pendingSearch = nil

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            resetToIdle()
            return
        }

        if trimmed == query, contentState != .error {
            return
        }

        let work = DispatchWorkItem { [weak self] in
            self?.performSearch(trimmed, forceRefresh: false)
        }
        pendingSearch = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    private func performSearch(_ text: String, forceRefresh: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            resetToIdle()
            return
        }

        pendingSearch?.cancel()
        pendingSearch = nil

        if !forceRefresh, trimmed == query, contentState == .results, !results.isEmpty {
            return
        }

        query = trimmed
        requestToken += 1
        let token = requestToken
        isLoading = true
        results.reset()
        contentState = .loading
        render()

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                async let discoursePage = self.client.discourses(page: 1,
                                                                 search: trimmed,
                                                                 forceRefresh: forceRefresh)
                async let trackPage = self.client.discourseAudios(page: 1,
                                                                 search: trimmed,
                                                                 forceRefresh: forceRefresh)
                let (discourses, tracks) = try await (discoursePage, trackPage)

                guard token == self.requestToken else { return }
                self.isLoading = false
                self.refreshControl.endRefreshing()
                self.results.append(discourses: discourses, tracks: tracks)
                self.seedLikeCounts(discourses: discourses.data, tracks: tracks.data)
                self.contentState = self.results.isEmpty ? .empty : .results
                self.render()
            } catch {
                guard token == self.requestToken else { return }
                self.isLoading = false
                self.refreshControl.endRefreshing()
                guard !Self.isCancellation(error) else { return }
                self.contentState = .error
                self.render()
            }
        }
    }

    private func loadNextPage() {
        guard contentState == .results, results.hasMore, !isLoading, !query.isEmpty else {
            return
        }

        isLoading = true
        let token = requestToken
        let nextPage = results.page + 1
        let search = query

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                async let discoursePage = self.client.discourses(page: nextPage, search: search)
                async let trackPage = self.client.discourseAudios(page: nextPage, search: search)
                let (discourses, tracks) = try await (discoursePage, trackPage)

                guard token == self.requestToken else { return }
                self.isLoading = false
                self.results.append(discourses: discourses, tracks: tracks)
                self.seedLikeCounts(discourses: discourses.data, tracks: tracks.data)
                self.tableView.reloadData()
            } catch {
                guard token == self.requestToken else { return }
                self.isLoading = false
                // Keep what is rendered; the next scroll retries this page.
            }
        }
    }

    // MARK: - Likes

    /// Records the counts that arrived with the payloads; a pending toggle keeps
    /// its optimistic count.
    private func seedLikeCounts(discourses: [Discourse], tracks: [DiscourseAudio]) {
        for discourse in discourses {
            likesStore.updateCount(discourse.totalLikes, for: .discourse(discourse.id))
        }
        for track in tracks {
            likesStore.updateCount(track.totalLikes, for: .audio(track.id))
        }
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

    /// Updates the rendered hearts in place after a toggle settles.
    @objc private func likesDidChange() {
        guard contentState == .results else {
            return
        }
        for indexPath in tableView.indexPathsForVisibleRows ?? [] {
            tableView.reloadRows(at: [indexPath], with: .none)
        }
    }

    private func resetToIdle() {
        pendingSearch?.cancel()
        pendingSearch = nil
        requestToken += 1
        isLoading = false
        query = ""
        results.reset()
        contentState = .idle
        refreshControl.endRefreshing()
        render()
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

    // MARK: - Actions

    @objc private func handleRefresh() {
        guard !query.isEmpty else {
            refreshControl.endRefreshing()
            return
        }
        performSearch(query, forceRefresh: true)
    }

    @objc private func playbackDidChange() {
        updatePlayingState()
    }

    private func updatePlayingState() {
        let audioID = playback.currentIdentity()?.audioID
        guard audioID != playingAudioID else {
            return
        }
        playingAudioID = audioID
        if contentState == .results {
            tableView.reloadData()
        }
    }

    // MARK: - Sections

    private var visibleSections: [Section] {
        Section.allCases.filter { numberOfRows(in: $0) > 0 }
    }

    private func section(at index: Int) -> Section? {
        let sections = visibleSections
        guard sections.indices.contains(index) else {
            return nil
        }
        return sections[index]
    }

    private func numberOfRows(in section: Section) -> Int {
        switch section {
        case .discourses:
            return results.discourses.count
        case .tracks:
            return results.tracks.count
        }
    }

    // MARK: - States

    private func render() {
        loadingIndicator.stopAnimating()

        switch contentState {
        case .idle:
            tableView.isHidden = true
            showState(symbolName: "magnifyingglass",
                      heading: NSLocalizedString("SEARCH_EMPTY_TITLE",
                                                comment: "Empty state heading on the Search tab"),
                      message: NSLocalizedString("SEARCH_EMPTY_MESSAGE",
                                                comment: "Empty state message on the Search tab"),
                      actionTitle: nil,
                      action: nil)
        case .loading:
            tableView.isHidden = true
            removeStateView()
            loadingIndicator.startAnimating()
        case .results:
            tableView.isHidden = false
            removeStateView()
            tableView.reloadData()
        case .empty:
            tableView.isHidden = true
            showState(symbolName: "magnifyingglass",
                      heading: NSLocalizedString("SEARCH_NO_RESULTS",
                                                comment: "Search results heading when nothing matches"),
                      message: String(format: NSLocalizedString("DISCOURSE_SEARCH_EMPTY_MESSAGE",
                                                               comment: "Search results message when nothing matches"),
                                      query),
                      actionTitle: nil,
                      action: nil)
        case .error:
            tableView.isHidden = true
            showState(symbolName: "wifi.exclamationmark",
                      heading: NSLocalizedString("DISCOURSE_SEARCH_ERROR_TITLE",
                                                comment: "Search heading when the request fails"),
                      message: DiscourseErrorCopy.serverFailure,
                      actionTitle: NSLocalizedString("DISCOURSE_CATALOGUE_RETRY",
                                                    comment: "Retry the search"),
                      action: { [weak self] in
                          guard let self else { return }
                          self.performSearch(self.query, forceRefresh: true)
                      })
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

    // MARK: - Theme

    @objc private func updateTheme() {
        let colors = DiscourseColors.current
        view.backgroundColor = colors.appBackground
        loadingIndicator.color = colors.accent
        refreshControl.tintColor = colors.accent
        searchController.searchBar.tintColor = colors.accent
        stateView?.updateTheme()
        tableView.reloadData()
    }
}

// MARK: - UISearchResultsUpdating

extension DiscourseSearchViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        scheduleSearch(for: searchController.searchBar.text ?? "")
    }
}

// MARK: - UISearchBarDelegate

extension DiscourseSearchViewController: UISearchBarDelegate {
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        pendingSearch?.cancel()
        pendingSearch = nil
        performSearch(searchBar.text ?? "", forceRefresh: false)
        searchBar.resignFirstResponder()
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        resetToIdle()
    }
}

// MARK: - UITableViewDataSource

extension DiscourseSearchViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return visibleSections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = self.section(at: section) else {
            return 0
        }
        return numberOfRows(in: section)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: DiscourseSearchCell.reuseIdentifier,
                                                 for: indexPath)
        guard let searchCell = cell as? DiscourseSearchCell,
              let section = self.section(at: indexPath.section) else {
            return cell
        }

        switch section {
        case .discourses:
            guard results.discourses.indices.contains(indexPath.row) else { return cell }
            let discourse = results.discourses[indexPath.row]
            searchCell.configure(with: discourse, like: likeState(for: discourse))
            searchCell.onOpen = { [weak self] in
                self?.openDiscourse(discourse)
            }
            searchCell.onToggleLike = { [weak self] in
                DiscourseLikeActions.toggleDiscourse(discourse, from: self)
            }
        case .tracks:
            guard results.tracks.indices.contains(indexPath.row) else { return cell }
            let track = results.tracks[indexPath.row]
            searchCell.configure(with: track,
                                 isPlaying: track.id == playingAudioID,
                                 like: likeState(for: track),
                                 download: DiscourseDownloadManager.shared.state(for: track.id))
            searchCell.onOpen = { [weak self] in
                self?.playback.play(track: track, discourse: nil)
            }
            searchCell.onToggleLike = { [weak self] in
                DiscourseLikeActions.toggleAudio(track, from: self)
            }
            searchCell.onToggleDownload = {
                DiscourseDownloadActions.toggle(track)
            }
        }
        return searchCell
    }
}

// MARK: - UITableViewDelegate

extension DiscourseSearchViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let section = self.section(at: section) else {
            return nil
        }

        let container = UIView()
        container.backgroundColor = .clear

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = DiscourseColors.current.secondaryText
        label.text = section.title
        label.isAccessibilityElement = true
        label.accessibilityTraits = .header

        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -20),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4)
        ])
        return container
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let section = section(at: indexPath.section) else {
            return
        }

        switch section {
        case .discourses:
            guard results.discourses.indices.contains(indexPath.row) else { return }
            openDiscourse(results.discourses[indexPath.row])
        case .tracks:
            guard results.tracks.indices.contains(indexPath.row) else { return }
            playback.play(track: results.tracks[indexPath.row], discourse: nil)
        }
    }

    private func openDiscourse(_ discourse: Discourse) {
        let detail = DiscourseDetailViewController(discourse: discourse,
                                                   likesStore: likesStore)
        navigationController?.pushViewController(detail, animated: true)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === tableView, !results.isEmpty else {
            return
        }

        let remaining = scrollView.contentSize.height - scrollView.contentOffset.y - scrollView.bounds.height
        if remaining < 400 {
            loadNextPage()
        }
    }
}
