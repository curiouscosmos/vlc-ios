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
    private let favourites = UIStackView()

    @objc @MainActor private func updateFavourites() {
        favourites.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let store = DiscourseLikesStore.shared
        let visible = DiscourseLikesStore.Collection.allCases.filter { store.hasPresentableFavourites(in: $0) }
        for kind in visible {
            let button = FavouriteCollectionButton()
            button.configure(collection: kind)
            button.heightAnchor.constraint(equalToConstant: 112).isActive = true
            button.addAction(UIAction { [weak self] _ in
                self?.navigationController?.pushViewController(FavouriteCollectionViewController(kind), animated: true)
            }, for: .touchUpInside)
            favourites.addArrangedSubview(button)
        }
        viewControllers.forEach { $0.additionalSafeAreaInsets.top = CGFloat(visible.count * 120) }
        favourites.isHidden = favourites.arrangedSubviews.isEmpty
        viewControllers.compactMap { $0 as? MediaCategoryViewController }.forEach {
            if $0.isViewLoaded { $0.updateEmptyState() }
        }
        view.bringSubviewToFront(favourites)
        applyForkTheme()
    }

    override init(mediaLibraryService: MediaLibraryService) {
        super.init(mediaLibraryService: mediaLibraryService)
        setupUI()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        favourites.axis = .vertical
        favourites.spacing = 8
        favourites.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(favourites)
        NSLayoutConstraint.activate([
            favourites.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            favourites.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            favourites.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(updateFavourites), name: .discourseLikesDidChange, object: nil)
        updateFavourites()
        Task { [weak self] in
            try? await DiscourseLikesStore.shared.refreshFavourites()
            await self?.updateFavourites()
        }
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
        favourites.tintColor = DiscourseColors.current.accent
        for button in favourites.arrangedSubviews {
            button.backgroundColor = DiscourseColors.current.trackSurface
            button.layer.cornerRadius = 12
            button.layer.borderWidth = 1
            button.layer.borderColor = DiscourseColors.current.trackBorder.cgColor
        }
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

/// Automatic collections have identities independent of media-library playlist names.
final class FavouriteCollectionButton: UIButton {
    private var artworkTask: Task<Void, Never>?

    func configure(collection: DiscourseLikesStore.Collection) {
        artworkTask?.cancel()
        let store = DiscourseLikesStore.shared
        let metadata = store.favouriteMetadata
        let urls = store.favouriteIDs(in: collection).compactMap { id in
            DiscourseURLResolver.resolve(collection == .tracks
                ? metadata.audios[id]?.discourseThumbnailURLString : metadata.discourses[id]?.thumbnailURLString)
        }
        var config = UIButton.Configuration.plain()
        config.title = collection.title
        config.subtitle = String(format: NSLocalizedString("TRACKS", comment: ""), store.favouriteIDs(in: collection).count)
        config.titleAlignment = .leading
        config.image = UIImage(systemName: "heart.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 44))
        config.imagePadding = 12
        configuration = config
        contentHorizontalAlignment = .leading
        accessibilityIdentifier = collection.rawValue
        artworkTask = Task { @MainActor [weak self] in
            guard let image = await Self.firstArtwork(urls: urls), !Task.isCancelled else { return }
            let size = CGSize(width: 112, height: 88)
            let artwork = UIGraphicsImageRenderer(size: size).image { _ in
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8).addClip()
                let scale = max(size.width / image.size.width, size.height / image.size.height)
                let scaled = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                image.draw(in: CGRect(x: (size.width - scaled.width) / 2,
                                      y: (size.height - scaled.height) / 2,
                                      width: scaled.width, height: scaled.height))
            }
            self?.configuration?.image = artwork
        }
    }

    static func firstArtwork(urls: [URL], load: (URL) async -> UIImage? = { url in
        if let cached = VLCThumbnailsCache.cachedImage(for: url) { return cached }
        let request = URLRequest(url: url)
        if let cached = URLCache.shared.cachedResponse(for: request),
           let image = VLCThumbnailsCache.image(from: cached.data, for: url, maxPixelSize: 120) { return image }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        guard let image = VLCThumbnailsCache.image(from: data, for: url, maxPixelSize: 120) else { return nil }
        URLCache.shared.storeCachedResponse(CachedURLResponse(response: response, data: data), for: request)
        return image
    }) async -> UIImage? {
        for url in urls {
            if Task.isCancelled { return nil }
            if let image = await load(url) { return image }
        }
        return nil
    }

}

private final class FavouriteCollectionViewController: UICollectionViewController {
    private let kind: DiscourseLikesStore.Collection
    private let store = DiscourseLikesStore.shared
    private var source: UICollectionViewDiffableDataSource<Int, String>!
    private var refreshTask: Task<Void, Never>?

    init(_ kind: DiscourseLikesStore.Collection) {
        self.kind = kind
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 8
        super.init(collectionViewLayout: layout)
        title = kind.title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.register(DiscourseCardCell.self, forCellWithReuseIdentifier: DiscourseCardCell.reuseIdentifier)
        collectionView.register(DiscourseHomeTrackCell.self, forCellWithReuseIdentifier: DiscourseHomeTrackCell.reuseIdentifier)
        collectionView.backgroundColor = DiscourseColors.current.appBackground
        collectionView.contentInset.bottom = discourseFloatingTabBarInset
        source = UICollectionViewDiffableDataSource<Int, String>(collectionView: collectionView) { [weak self] view, index, id in
            guard let self else { return nil }
            let metadata = self.store.favouriteMetadata
            let target = DiscourseLikesStore.Target(id: id, isAudio: self.kind == .tracks)
            let unavailable = metadata.unavailable.contains(target.storageKey)
            if self.kind == .discourses {
                let saved = metadata.discourses[id]
                let discourse = saved ?? Discourse(id: id, title: NSLocalizedString("Unavailable discourse", comment: "Favourite without metadata"))
                let cell = view.dequeueReusableCell(withReuseIdentifier: DiscourseCardCell.reuseIdentifier, for: index) as! DiscourseCardCell
                cell.layoutStyle = .list
                cell.configure(with: discourse, like: .resolve(target: target, payloadLikes: discourse.totalLikes),
                               downloads: .resolve(discourseID: id, totalTracks: discourse.totalTracks))
                cell.isPlaybackAvailable = saved != nil && !unavailable
                cell.onOpen = { [weak self] in
                    guard let self, saved != nil, !unavailable else { return }
                    self.navigationController?.pushViewController(DiscourseDetailViewController(discourse: discourse), animated: true)
                }
                cell.onToggleLike = { [weak self] in DiscourseLikeActions.toggleDiscourse(discourse, from: self) }
                return cell
            }
            let saved = metadata.audios[id]
            let audio = saved ?? DiscourseAudio(id: id, discourseID: "", discourseName: "",
                title: NSLocalizedString("Unavailable track", comment: "Favourite without metadata"), audioURLString: "")
            let cell = view.dequeueReusableCell(withReuseIdentifier: DiscourseHomeTrackCell.reuseIdentifier, for: index) as! DiscourseHomeTrackCell
            cell.configure(with: audio, isPlaying: false, like: .resolve(target: target, payloadLikes: audio.totalLikes),
                           download: DiscourseDownloadManager.shared.state(for: id))
            cell.isPlaybackAvailable = saved != nil && !unavailable
            cell.onOpen = { [weak self] in self?.play(id: id) }
            cell.onToggleLike = { [weak self] in DiscourseLikeActions.toggleAudio(audio, from: self) }
            cell.onToggleDownload = unavailable || saved == nil ? nil : { DiscourseDownloadActions.toggle(audio) }
            return cell
        }
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .discourseLikesDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .discourseDownloadsDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .VLCThemeDidChangeNotification, object: nil)
        collectionView.refreshControl = UIRefreshControl()
        collectionView.refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
        reload()
        refresh()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let layout = collectionViewLayout as! UICollectionViewFlowLayout
        let size = CGSize(width: collectionView.bounds.width, height: kind == .tracks ? 100 : 160)
        if layout.itemSize != size { layout.itemSize = size }
    }

    @objc private func reload() {
        collectionView.backgroundColor = DiscourseColors.current.appBackground
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(store.favouriteIDs(in: kind))
        let empty = UILabel()
        empty.text = NSLocalizedString("Use the heart controls to add favourites.", comment: "Empty automatic collection")
        empty.textAlignment = .center
        empty.numberOfLines = 0
        empty.textColor = .secondaryLabel
        collectionView.backgroundView = snapshot.itemIdentifiers.isEmpty ? empty : nil
        snapshot.reconfigureItems(snapshot.itemIdentifiers.filter { source.snapshot().indexOfItem($0) != nil })
        source.apply(snapshot, animatingDifferences: false)
    }

    @objc private func refresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.collectionView.refreshControl?.endRefreshing(); self.refreshTask = nil }
            do {
                try await self.store.refreshFavourites()
                self.navigationItem.rightBarButtonItem = nil
            } catch {
                self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Retry", comment: "Retry favourites"),
                    style: .plain, target: self, action: #selector(self.refresh))
            }
            self.reload()
        }
    }

    private func play(id: String) {
        let metadata = store.favouriteMetadata
        let tracks = store.favouriteIDs(in: .tracks).filter {
            !metadata.unavailable.contains(DiscourseLikesStore.Target.audio($0).storageKey)
        }.compactMap { metadata.audios[$0] }
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        DiscoursePlayback.shared.play(tracks: tracks, discourse: nil, startingAt: index)
    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if let cell = collectionView.cellForItem(at: indexPath) as? DiscourseCardCell { cell.onOpen?() }
        if let cell = collectionView.cellForItem(at: indexPath) as? DiscourseHomeTrackCell { cell.onOpen?() }
    }
}
