/*****************************************************************************
 * DiscourseCatalogueViewController.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * The remote catalogue: a full-width list of discourse cards (artwork left,
 * content right) with paging, pull-to-refresh, a language filter and the
 * most-liked sort. The last language/sort selection is restored from
 * DiscourseCatalogueFilterStore.
 *
 * Loading rules follow the brief: cached pages render instantly, a failed
 * request never erases rendered content, and a force refresh bypasses the cache.
 *****************************************************************************/

import UIKit

final class DiscourseCatalogueViewController: UIViewController {
    private let client: DiscourseAPIClient
    private let filterStore: DiscourseCatalogueFilterStore
    private let likesStore: DiscourseLikesStore

    private var collectionView: UICollectionView!
    private let refreshControl = UIRefreshControl()
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    private var filterButton: UIBarButtonItem!
    private var stateView: DiscourseEmptyStateView?

    private let alphabetIndex = UIStackView()
    private var sections: [(title: String, items: [Discourse])] = []
    private var pendingLetter: String?
    private var discourses: [Discourse] = []
    private var currentPage = 0
    private var totalPages = 1
    private var isLoadingNextPage = false
    private var hasLoaded = false
    /// Bumped for every first-page request so stale answers (an old filter, a
    /// racing retry) are dropped instead of overwriting newer content.
    private var requestToken = 0

    init(client: DiscourseAPIClient = .shared,
         filterStore: DiscourseCatalogueFilterStore = .shared,
         likesStore: DiscourseLikesStore = .shared) {
        self.client = client
        self.filterStore = filterStore
        self.likesStore = likesStore
        super.init(nibName: nil, bundle: nil)
        title = NSLocalizedString("DISCOURSES", comment: "Discourses tab title")
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
        setupFilterButton()
        setupCollectionView()
        setupAlphabetIndex()
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
                                               selector: #selector(downloadsDidChange),
                                               name: .discourseDownloadsDidChange,
                                               object: nil)
        addMiniPlayerObservers()
        updateTheme()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateMiniPlayerInset()
        if !hasLoaded {
            loadFirstPage(forceRefresh: false)
        }
    }

    // MARK: - Setup

    private func addMiniPlayerObservers() {
        let names = [VLCPlayerDisplayControllerDisplayMiniPlayer, VLCPlayerDisplayControllerHideMiniPlayer]
        for name in names {
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(updateMiniPlayerInset),
                                                   name: NSNotification.Name(rawValue: name),
                                                   object: nil)
        }
    }

    /// The mini player floats above the tab bar, so the last cards scroll clear
    /// of it instead of hiding underneath.
    @objc private func updateMiniPlayerInset() {
        let visible = PlaybackService.sharedInstance().playerDisplayController.isMiniPlayerVisible
        collectionView.contentInset.bottom = (visible ? CGFloat(AudioMiniPlayer.height) : 0)
            + discourseFloatingTabBarInset
        collectionView.verticalScrollIndicatorInsets.bottom = collectionView.contentInset.bottom
    }

    private func setupCollectionView() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.accessibilityIdentifier = "discourseCatalogue"
        collectionView.register(DiscourseHomeSectionHeaderView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: DiscourseHomeSectionHeaderView.reuseIdentifier)
        collectionView.register(DiscourseCardCell.self,
                                forCellWithReuseIdentifier: DiscourseCardCell.reuseIdentifier)

        refreshControl.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        collectionView.refreshControl = refreshControl

        view.addSubview(alphabetIndex)
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: alphabetIndex.leadingAnchor),
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

    private func setupFilterButton() {
        filterButton = UIBarButtonItem(image: UIImage(systemName: "line.3.horizontal.decrease.circle"),
                                       style: .plain,
                                       target: nil,
                                       action: nil)
        filterButton.accessibilityLabel = NSLocalizedString("DISCOURSE_FILTER_TITLE",
                                                            comment: "Catalogue filter button")
        filterButton.accessibilityIdentifier = "discourseFilter"
        navigationItem.rightBarButtonItem = filterButton
        updateFilterButton()
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1),
                                              heightDimension: .estimated(112))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1),
                                               heightDimension: .estimated(112))
        let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 12
        section.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 24, trailing: 16)
        let header = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(36)),
            elementKind: UICollectionView.elementKindSectionHeader, alignment: .top)
        section.boundarySupplementaryItems = filterStore.sort == nil ? [header] : []
        return UICollectionViewCompositionalLayout(section: section)
    }

    static func indexLetter(for title: String) -> String {
        let folded = title.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .uppercased()
        guard let first = folded.first, ("A"..."Z").contains(String(first)) else { return "#" }
        return String(first)
    }

    private func setupAlphabetIndex() {
        alphabetIndex.translatesAutoresizingMaskIntoConstraints = false
        alphabetIndex.axis = .vertical
        alphabetIndex.distribution = .fillEqually
        NSLayoutConstraint.activate([
            alphabetIndex.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            alphabetIndex.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            alphabetIndex.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                                                  constant: -discourseFloatingTabBarInset - CGFloat(AudioMiniPlayer.height)),
            alphabetIndex.widthAnchor.constraint(equalToConstant: 28)
        ])
        for letter in Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map({ String($0) }) + ["#"] {
            let button = UIButton(type: .system)
            button.setTitle(letter, for: .normal)
            button.setTitleColor(DiscourseColors.current.secondaryText, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 12)
            button.accessibilityLabel = letter
            button.addAction(UIAction { [weak self] _ in
                self?.pendingLetter = letter
                self?.scrollToPendingLetter()
            }, for: .touchUpInside)
            alphabetIndex.addArrangedSubview(button)
        }
    }

    private func reloadCatalogue() {
        if filterStore.sort == nil {
            let grouped = Dictionary(grouping: discourses) { Self.indexLetter(for: $0.title) }
            sections = grouped.keys.sorted { $0 == "#" ? false : ($1 == "#" || $0 < $1) }.map { letter in
                (letter, grouped[letter]!.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending })
            }
        } else {
            sections = discourses.isEmpty ? [] : [("", discourses)]
        }
        alphabetIndex.isHidden = filterStore.sort != nil || discourses.isEmpty || collectionView.isHidden
        collectionView.reloadData()
    }

    private func scrollToPendingLetter() {
        guard let letter = pendingLetter else { return }
        // Finish paging before jumping so a letter also reaches titles outside the loaded pages.
        if currentPage < totalPages {
            loadNextPage()
            return
        }
        pendingLetter = nil
        guard let section = sections.firstIndex(where: { $0.title == letter }) else { return }
        collectionView.layoutIfNeeded()
        let path = IndexPath(item: 0, section: section)
        if let header = collectionView.layoutAttributesForSupplementaryElement(
            ofKind: UICollectionView.elementKindSectionHeader, at: path) {
            let top = -collectionView.adjustedContentInset.top
            let bottom = max(top, collectionView.contentSize.height - collectionView.bounds.height + collectionView.adjustedContentInset.bottom)
            let offset = min(bottom, max(top, header.frame.minY + top))
            collectionView.setContentOffset(CGPoint(x: 0, y: offset), animated: true)
        }
    }

    private func discourse(at indexPath: IndexPath) -> Discourse {
        sections[indexPath.section].items[indexPath.item]
    }

    // MARK: - Filters

    private func updateFilterButton() {
        let active = filterStore.hasActiveFilters
        filterButton.image = UIImage(systemName: active ? "line.3.horizontal.decrease.circle.fill"
                                                        : "line.3.horizontal.decrease.circle")
        filterButton.menu = makeFilterMenu()
    }

    private func makeFilterMenu() -> UIMenu {
        let language = filterStore.language
        var languageActions: [UIAction] = [
            UIAction(title: NSLocalizedString("DISCOURSE_FILTER_ALL_LANGUAGES",
                                              comment: "Catalogue filter: no language filter"),
                     state: language == nil ? .on : .off) { [weak self] _ in
                self?.applyFilters { $0.language = nil }
            }
        ]
        for value in DiscourseLanguage.allCases {
            languageActions.append(UIAction(title: value.displayName,
                                            state: language == value ? .on : .off) { [weak self] _ in
                self?.applyFilters { $0.language = value }
            })
        }

        let sort = filterStore.sort
        let sortActions: [UIAction] = [
            UIAction(title: NSLocalizedString("DISCOURSE_FILTER_SORT_DEFAULT",
                                              comment: "Catalogue sort: default order"),
                     state: sort == nil ? .on : .off) { [weak self] _ in
                self?.applyFilters { $0.sort = nil }
            },
            UIAction(title: NSLocalizedString("DISCOURSE_FILTER_SORT_MOST_LIKED",
                                              comment: "Catalogue sort: most liked first"),
                     state: sort == .mostLiked ? .on : .off) { [weak self] _ in
                self?.applyFilters { $0.sort = .mostLiked }
            }
        ]

        var children: [UIMenuElement] = [
            UIMenu(title: NSLocalizedString("DISCOURSE_FILTER_LANGUAGE",
                                            comment: "Catalogue filter: language"),
                   options: .displayInline,
                   children: languageActions),
            UIMenu(title: NSLocalizedString("DISCOURSE_FILTER_SORT",
                                            comment: "Catalogue filter: sort order"),
                   children: sortActions)
        ]

        if filterStore.hasActiveFilters {
            children.append(UIAction(title: NSLocalizedString("DISCOURSE_FILTER_CLEAR",
                                                              comment: "Clear the catalogue filters"),
                                     image: UIImage(systemName: "xmark.circle"),
                                     attributes: .destructive) { [weak self] _ in
                self?.applyFilters { $0.reset() }
            })
        }

        return UIMenu(children: children)
    }

    private func applyFilters(_ change: (DiscourseCatalogueFilterStore) -> Void) {
        change(filterStore)
        updateFilterButton()
        collectionView.setCollectionViewLayout(makeLayout(), animated: false)
        pendingLetter = nil
        discourses = []
        currentPage = 0
        totalPages = 1
        reloadCatalogue()
        loadFirstPage(forceRefresh: false)
    }

    // MARK: - Loading

    @objc private func handleRefresh() {
        loadFirstPage(forceRefresh: true)
    }

    private func loadFirstPage(forceRefresh: Bool) {
        pendingLetter = nil
        requestToken += 1
        let token = requestToken
        isLoadingNextPage = false

        if discourses.isEmpty {
            if !forceRefresh,
               let cached = client.cachedDiscourses(page: 1,
                                                    language: filterStore.language,
                                                    sort: filterStore.sort),
               !cached.data.isEmpty {
                discourses = cached.data
                seedLikeCounts(cached.data)
                currentPage = cached.meta.page
                totalPages = cached.meta.totalPages
                hasLoaded = true
                reloadCatalogue()
                showContent()
            } else {
                showLoading()
            }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let page = try await self.client.discourses(page: 1,
                                                            language: self.filterStore.language,
                                                            sort: self.filterStore.sort,
                                                            forceRefresh: forceRefresh)
                guard token == self.requestToken else { return }

                self.discourses = page.data
                self.seedLikeCounts(page.data)
                self.currentPage = page.meta.page
                self.totalPages = page.meta.totalPages
                self.hasLoaded = true
                self.refreshControl.endRefreshing()
                self.reloadCatalogue()

                if self.discourses.isEmpty {
                    self.showEmptyCatalogueState()
                } else {
                    self.showContent()
                }
            } catch {
                guard token == self.requestToken else { return }
                self.refreshControl.endRefreshing()
                guard !Self.isCancellation(error) else { return }

                // A failed request never erases what is already rendered.
                if self.discourses.isEmpty {
                    self.showErrorState()
                } else {
                    self.showContent()
                }
            }
        }
    }

    private func loadNextPage() {
        guard hasLoaded, !isLoadingNextPage, currentPage < totalPages else {
            return
        }

        isLoadingNextPage = true
        let token = requestToken
        let nextPage = currentPage + 1

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let page = try await self.client.discourses(page: nextPage,
                                                            language: self.filterStore.language,
                                                            sort: self.filterStore.sort,
                                                            forceRefresh: false)
                guard token == self.requestToken else {
                    self.isLoadingNextPage = false
                    return
                }

                self.isLoadingNextPage = false
                self.currentPage = page.meta.page
                self.totalPages = page.meta.totalPages

                let known = Set(self.discourses.map(\.id))
                let fresh = page.data.filter { !known.contains($0.id) }
                self.discourses.append(contentsOf: fresh)
                self.seedLikeCounts(fresh)
                self.reloadCatalogue()
                self.scrollToPendingLetter()
            } catch {
                guard token == self.requestToken else {
                    self.isLoadingNextPage = false
                    return
                }
                self.isLoadingNextPage = false
            }
        }
    }

    /// Records the counts that arrived with a payload; a pending toggle keeps
    /// its optimistic count.
    private func seedLikeCounts(_ discourses: [Discourse]) {
        for discourse in discourses {
            likesStore.updateCount(discourse.totalLikes, for: .discourse(discourse.id))
        }
    }

    /// Updates the rendered hearts in place after a toggle settles.
    /// Updates the rendered download badges in place.
    @objc private func downloadsDidChange() {
        for cell in collectionView.visibleCells {
            guard let card = cell as? DiscourseCardCell,
                  let indexPath = collectionView.indexPath(for: card),
                  sections.indices.contains(indexPath.section),
                  sections[indexPath.section].items.indices.contains(indexPath.item) else {
                continue
            }
            let discourse = discourse(at: indexPath)
            card.configure(with: discourse,
                           like: likeState(for: discourse),
                           downloads: downloadSummary(for: discourse))
        }
    }

    private func likeState(for discourse: Discourse) -> DiscourseLikeState {
        return DiscourseLikeState.resolve(target: .discourse(discourse.id),
                                          payloadLikes: discourse.totalLikes,
                                          store: likesStore)
    }

    private func downloadSummary(for discourse: Discourse) -> DiscourseDownloadSummary {
        return DiscourseDownloadSummary.resolve(discourseID: discourse.id,
                                                totalTracks: discourse.totalTracks)
    }

    @objc private func likesDidChange() {
        for cell in collectionView.visibleCells {
            guard let card = cell as? DiscourseCardCell,
                  let indexPath = collectionView.indexPath(for: card),
                  sections.indices.contains(indexPath.section),
                  sections[indexPath.section].items.indices.contains(indexPath.item) else {
                continue
            }
            let discourse = discourse(at: indexPath)
            card.configure(with: discourse,
                           like: likeState(for: discourse),
                           downloads: downloadSummary(for: discourse))
        }
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

    // MARK: - States

    private func showLoading() {
        removeStateView()
        alphabetIndex.isHidden = true
        collectionView.isHidden = true
        loadingIndicator.startAnimating()
    }

    private func showContent() {
        removeStateView()
        loadingIndicator.stopAnimating()
        collectionView.isHidden = false
        alphabetIndex.isHidden = filterStore.sort != nil || discourses.isEmpty
    }

    private func showEmptyCatalogueState() {
        showState(symbolName: "book.closed",
                  heading: NSLocalizedString("DISCOURSE_CATALOGUE_EMPTY_TITLE",
                                            comment: "Empty catalogue heading"),
                  message: NSLocalizedString("DISCOURSE_CATALOGUE_EMPTY_MESSAGE",
                                            comment: "Empty catalogue message"),
                  actionTitle: NSLocalizedString("DISCOURSE_CATALOGUE_RELOAD",
                                                 comment: "Reload the catalogue")) { [weak self] in
            self?.loadFirstPage(forceRefresh: true)
        }
    }

    private func showErrorState() {
        showState(symbolName: "wifi.exclamationmark",
                  heading: NSLocalizedString("DISCOURSE_CATALOGUE_ERROR_TITLE",
                                            comment: "Failed catalogue heading"),
                  message: DiscourseErrorCopy.serverFailure,
                  actionTitle: NSLocalizedString("DISCOURSE_CATALOGUE_RETRY",
                                                 comment: "Retry loading the catalogue")) { [weak self] in
            self?.loadFirstPage(forceRefresh: true)
        }
    }

    private func showState(symbolName: String,
                           heading: String,
                           message: String,
                           actionTitle: String,
                           action: (() -> Void)?) {
        removeStateView()
        loadingIndicator.stopAnimating()
        alphabetIndex.isHidden = true
        collectionView.isHidden = true

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
        alphabetIndex.tintColor = colors.accent
        loadingIndicator.color = colors.accent
        refreshControl.tintColor = colors.accent
        stateView?.updateTheme()
        reloadCatalogue()
    }
}

// MARK: - UICollectionViewDataSource

extension DiscourseCatalogueViewController: UICollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int { sections.count }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind,
            withReuseIdentifier: DiscourseHomeSectionHeaderView.reuseIdentifier, for: indexPath)
        if let header = header as? DiscourseHomeSectionHeaderView {
            header.configure(title: sections[indexPath.section].title)
            header.backgroundColor = DiscourseColors.current.searchFieldBackground
            header.layer.cornerRadius = 10
        }
        return header
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return sections[section].items.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: DiscourseCardCell.reuseIdentifier,
                                                      for: indexPath)
        guard let card = cell as? DiscourseCardCell,
              sections.indices.contains(indexPath.section),
              sections[indexPath.section].items.indices.contains(indexPath.item) else {
            return cell
        }
        let discourse = discourse(at: indexPath)
        card.layoutStyle = .list
        card.configure(with: discourse,
                       like: likeState(for: discourse),
                       downloads: downloadSummary(for: discourse))
        card.onOpen = { [weak self, weak card] in
            guard let self, let card,
                  let path = self.collectionView.indexPath(for: card) else { return }
            self.openDiscourse(self.discourse(at: path))
        }
        card.onToggleLike = { [weak self] in
            DiscourseLikeActions.toggleDiscourse(discourse, from: self)
        }
        return card
    }
}

// MARK: - UICollectionViewDelegate

extension DiscourseCatalogueViewController: UICollectionViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === collectionView,
              !discourses.isEmpty,
              !collectionView.isHidden,
              collectionView.window != nil,
              scrollView.contentSize.height > 0 else {
            return
        }

        if let first = collectionView.indexPathsForVisibleItems.sorted().first,
           sections.indices.contains(first.section) {
            let letter = sections[first.section].title
            for case let button as UIButton in alphabetIndex.arrangedSubviews {
                button.backgroundColor = button.currentTitle == letter ? DiscourseColors.current.accent : .clear
                button.setTitleColor(button.currentTitle == letter ? DiscourseColors.current.appBackground
                    : DiscourseColors.current.secondaryText, for: .normal)
                button.layer.cornerRadius = 12
            }
        }
        let remaining = scrollView.contentSize.height - scrollView.contentOffset.y - scrollView.bounds.height
        if remaining < 400 {
            loadNextPage()
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        openDiscourse(discourse(at: indexPath))
    }

    private func openDiscourse(_ discourse: Discourse) {
        let detail = DiscourseDetailViewController(discourse: discourse, likesStore: likesStore)
        navigationController?.pushViewController(detail, animated: true)
    }
}
