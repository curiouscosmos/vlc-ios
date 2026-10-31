/*****************************************************************************
 * AudioPlayerViewController.swift
 * VLC for iOS
 *****************************************************************************
 * Copyright © 2022-2023 VLC authors and VideoLAN
 *
 * Authors: Diogo Simao Marques <dogo@videolabs.io>
 *
 * Refer to the COPYING file of the official project for license.
 *****************************************************************************/

import UIKit

#if os(iOS)
import WidgetKit
#endif

@objc(VLCAudioPlayerViewControllerDelegate)
protocol AudioPlayerViewControllerDelegate: AnyObject {
    func audioPlayerViewControllerDidMinimize(_ audioPlayerViewController: AudioPlayerViewController)
    func audioPlayerViewControllerDidClose(_ audioPlayerViewController: AudioPlayerViewController)
    func audioPlayerViewControllerShouldBeDisplayed(_ audioPlayerViewController: AudioPlayerViewController) -> Bool
    func audioPlayerViewControllerShouldSwitchPlayer(_ audioPlayerViewController: AudioPlayerViewController)
}

@objc(VLCAudioPlayerViewController)
class AudioPlayerViewController: PlayerViewController {
    // MARK: - Properties

    @objc weak var delegate: AudioPlayerViewControllerDelegate?

    private var isQueueHidden: Bool = true


    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        get { return UIInterfaceOrientationMask.allButUpsideDown }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override var canBecomeFirstResponder: Bool {
        return true
    }

    lazy var audioPlayerView: AudioPlayerView = {
        let audioPlayerView = AudioPlayerView(frame: .zero)
        audioPlayerView.delegate = self
        return audioPlayerView
    }()

    private lazy var moreOptionsButton: UIButton = {
        let moreOptionsButton = UIButton(type: .custom)
        moreOptionsButton.setImage(UIImage(named: "iconMoreOptions"), for: .normal)
        moreOptionsButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        moreOptionsButton.addTarget(self, action: #selector(handleMoreOptionsButton), for: .touchUpInside)
        moreOptionsButton.accessibilityIdentifier = VLCAccessibilityIdentifier.moreOptions
        return moreOptionsButton
    }()

#if os(iOS)
    /// Fork-only: the like control of the discourse track being played. Hidden
    /// unless the current media carries a discourse identity whose payload is
    /// still in `DiscourseTrackRegistry` (a queue restored from the last-played
    /// playlist has no payload, so the heart stays away instead of guessing).
    private lazy var discourseLikeButton: DiscourseLikeControl = {
        let control = DiscourseLikeControl()
        control.style = .player
        control.isHidden = true
        control.accessibilityIdentifier = VLCAccessibilityIdentifier.discourseLike
        control.addTarget(self, action: #selector(toggleDiscourseLike), for: .touchUpInside)
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()
#endif

    // MARK: - Init

#if os(iOS)
    @objc init(mediaLibraryService: MediaLibraryService,
               rendererDiscovererManager: VLCRendererDiscovererManager,
               playerController: PlayerController) {
        super.init(mediaLibraryService: mediaLibraryService,
                   rendererDiscovererManager: rendererDiscovererManager,
                   playerController: playerController,
                   isBrightnessControlAvailable: false)

        self.playerController.delegate = self
        mediaNavigationBar.addMoreOptionsButton(moreOptionsButton)
        setupDiscourseLikeButton()
        audioPlayerView.setupNavigationBar(with: mediaNavigationBar)
        audioPlayerView.updateThumbnailImageView()
        refreshPlaybackSpeed()
        audioPlayerView.setupBackgroundColor()
        mediaScrubProgressBar.updateBackgroundAlpha(with: 0.0)
        audioPlayerView.setupProgressView(with: mediaScrubProgressBar)
        audioPlayerView.setupExternalOutputView(with: externalOutputView)
        setupAudioPlayerViewConstraints()
        setupOptionsNavigationBar()
        setupSliders()
        setupStatusLabel()
        setupLoadingIndicator()
    }
#else
    @objc override init(mediaLibraryService: MediaLibraryService, playerController: PlayerController) {
        super.init(mediaLibraryService: mediaLibraryService, playerController: playerController)

        self.playerController.delegate = self
        mediaNavigationBar.addMoreOptionsButton(moreOptionsButton)
        audioPlayerView.setupNavigationBar(with: mediaNavigationBar)
        audioPlayerView.updateThumbnailImageView()
        refreshPlaybackSpeed()
        audioPlayerView.setupBackgroundColor()
        mediaScrubProgressBar.updateBackgroundAlpha(with: 0.0)
        audioPlayerView.setupProgressView(with: mediaScrubProgressBar)
        audioPlayerView.setupExternalOutputView(with: externalOutputView)
        setupAudioPlayerViewConstraints()
        setupOptionsNavigationBar()
        setupStatusLabel()
        setupLoadingIndicator()
    }
#endif

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

#if os(iOS)
    // MARK: - Fork: discourse likes

    deinit { clipTimer?.invalidate() }

    private static let clipCleanup: Void = DiscourseClipExporter.cleanInterruptedExports()
    private var clipEditor: DiscourseClipEditor?
    private var clipTrackID: String?
    private var clipTimer: Timer?
    private var clipPreview = DiscourseClipPreview()
    private var clipPausedAtEnd = false
    private lazy var clipButton = playerAction(symbol: "scissors", action: #selector(toggleClip))

    private func endClipEditing() {
        clipTimer?.invalidate()
        clipTimer = nil
        clipEditor?.removeFromSuperview()
        clipEditor = nil
        clipTrackID = nil
        resetClipPreviewState()
        mediaScrubProgressBar.isHidden = false
        audioPlayerView.setClipEditing(false)
        clipButton.configuration?.baseForegroundColor = .white
        clipButton.configuration?.background.backgroundColor = .clear
    }

    private func resetClipPreviewState() {
        clipPreview = DiscourseClipPreview()
        clipPausedAtEnd = false
    }

    @objc private func clipEnteredBackground() {
        guard clipEditor != nil else { return }
        playbackService.pause()
        endClipEditing()
    }

    @objc private func toggleClip() {
        if clipEditor != nil { endClipEditing(); return }
        let duration = Double(playbackService.mediaDuration) / 1000
        guard let track = currentDiscourseTrack(), playbackService.isSeekable, duration.isFinite, duration >= 1 else { return }
        guard DiscourseDownloadStore.shared.localURL(for: track.id) != nil else {
            let prompt = DiscourseClipDownloadPrompt { DiscourseDownloadManager.shared.download(track) }
            prompt.modalPresentationStyle = .overFullScreen
            prompt.modalTransitionStyle = .crossDissolve
            present(prompt, animated: true)
            return
        }
        let editor = DiscourseClipEditor(range: DiscourseClipRange(duration: duration, position: Double(playbackService.playbackPosition) * duration))
        // Clipping is a deliberate edit: stop the music so the range can be
        // adjusted and previewed from the start bracket.
        if playbackService.isPlaying { playbackService.pause() }
        resetClipPreviewState()
        clipEditor = editor
        clipTrackID = track.id
        editor.translatesAutoresizingMaskIntoConstraints = false
        audioPlayerView.progressionView.addSubview(editor)
        NSLayoutConstraint.activate([
            editor.leadingAnchor.constraint(equalTo: audioPlayerView.progressionView.leadingAnchor, constant: 12),
            editor.trailingAnchor.constraint(equalTo: audioPlayerView.progressionView.trailingAnchor, constant: -12),
            editor.topAnchor.constraint(equalTo: audioPlayerView.progressionView.topAnchor),
            editor.bottomAnchor.constraint(equalTo: audioPlayerView.progressionView.bottomAnchor)
        ])
        mediaScrubProgressBar.isHidden = true
        audioPlayerView.setClipEditing(true)
        clipButton.configuration?.baseForegroundColor = DiscourseColors.current.accent
        clipButton.configuration?.cornerStyle = .capsule
        clipButton.configuration?.background.backgroundColor = DiscourseColors.current.accent.withAlphaComponent(0.25)
        editor.seek = { [weak self, weak editor] seconds in
            guard let self, let editor else { return }
            self.clipPausedAtEnd = false
            if self.playbackService.isPlaying {
                self.clipPreview = DiscourseClipPreview()
                self.playbackService.seek(toMilliseconds: Int(seconds * 1000))
            } else {
                self.clipPreview.requestStart(at: seconds)
                editor.setPosition(seconds)
            }
        }
        editor.startDidChange = { [weak self, weak editor] seconds in
            guard let self, let editor else { return }
            self.clipPausedAtEnd = false
            self.clipPreview.requestStart(at: seconds)
            if !self.playbackService.isPlaying { editor.setPosition(seconds) }
        }
        editor.cut = { [weak self, weak editor] in
            guard let self, let editor else { return }
            self.playbackService.pause()
            let sheet = UINavigationController(rootViewController: DiscourseClipSaveController(track: track, range: editor.range))
            sheet.sheetPresentationController?.detents = [.medium()]
            sheet.sheetPresentationController?.prefersGrabberVisible = true
            self.present(sheet, animated: true)
        }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.updateClipPreview() }
        RunLoop.main.add(timer, forMode: .common)
        clipTimer = timer
    }

    private func updateClipPreview() {
        guard let editor = clipEditor else { return }
        guard currentDiscourseTrack()?.id == clipTrackID else { endClipEditing(); return }
        let position = Double(playbackService.playedTime().intValue) / 1000
        if let target = clipPreview.seekTarget(position: position, isPlaying: playbackService.isPlaying,
                                              isInteracting: editor.isUserInteracting) {
            playbackService.seek(toMilliseconds: Int(target * 1000))
            return
        }
        guard !editor.isUserInteracting else { return }
        guard playbackService.isPlaying else {
            editor.setPosition(clipPreview.pendingStart ?? (clipPausedAtEnd ? editor.range.end : position))
            return
        }
        // Let the explicit start seek run before checking the previous position
        // against the end bracket. A stale tick must never initiate another seek.
        guard clipPreview.pendingStart == nil else { return }
        editor.setPosition(position)
        if position >= editor.range.end, !clipPausedAtEnd {
            clipPausedAtEnd = true
            playbackService.pause()
            editor.setPosition(editor.range.end)
        }
    }

    private var playlistActions: EditActions?
    private lazy var discourseButton = playerAction(symbol: "text.bubble", action: #selector(openDiscourse))
    private lazy var playlistButton = playerAction(symbol: "text.badge.plus", action: #selector(addCurrentTrackToPlaylist))
    private let playerDownloadControl = DiscourseDownloadControl(iconSize: 28)
    private lazy var noiseButton = playerAction(symbol: "waveform.slash", action: #selector(toggleNoise))

    private func playerAction(symbol: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: symbol)
        configuration.baseForegroundColor = .white
        configuration.contentInsets = .zero
        button.configuration = configuration
        if symbol == "scissors" {
            button.configurationUpdateHandler = { [weak self] button in
                guard let self else { return }
                let colors = DiscourseColors.current
                if !button.isEnabled && !colors.isDark {
                    button.configuration?.baseForegroundColor = colors.accent
                    button.configuration?.background.backgroundColor = colors.accent.withAlphaComponent(0.12)
                    button.configuration?.cornerStyle = .capsule
                } else {
                    button.configuration?.baseForegroundColor = self.clipEditor == nil ? .white : colors.accent
                    button.configuration?.background.backgroundColor = self.clipEditor == nil
                        ? .clear
                        : colors.accent.withAlphaComponent(0.25)
                }
            }
        }
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc private func openDiscourse() {
        guard let identity = currentDiscourseIdentity(),
              !identity.discourseID.isEmpty,
              let url = URL(string: "https://rajneeshdiscourse.com/discourses/\(identity.discourseID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? identity.discourseID)") else { return }
        dismiss(animated: true) {
            _ = VLCAppCoordinator.sharedInstance().handleDiscourseDeepLink(url)
        }
    }

    @objc private func addCurrentTrackToPlaylist() {
        guard let url = playbackService.currentlyPlayingMedia?.url,
              let media = mediaLibraryService.fetchOrCreateMedia(with: url) else { return }
        let actions = EditActions(model: PlaylistModel(medialibrary: mediaLibraryService), mediaLibraryService: mediaLibraryService, presentingViewController: self)
        actions.objects = [media]
        playlistActions = actions
        actions.addToPlaylist()
    }

    @objc private func togglePlayerDownload() {
        guard let track = currentDiscourseTrack() else { return }
        DiscourseDownloadActions.toggle(track)
    }

    private func refreshPlayerDownload() {
        let track = currentDiscourseTrack()
        playerDownloadControl.isEnabled = track != nil
        playerDownloadControl.alpha = 1
        playerDownloadControl.configure(with: track.map { DiscourseDownloadManager.shared.state(for: $0.id) } ?? .missing,
                                        title: track?.title ?? "")
    }

    @objc private func toggleNoise() {
        _ = playbackService.setNoiseReduction(enabled: !playbackService.noiseReductionEnabled)
        refreshNoiseButton()
    }

    /// The prepared RNNoise filter only reports readiness once the audio output
    /// exists, which can happen after `PlaybackDidStart` (and again whenever the
    /// output is rebuilt). Re-check on the player's position ticks so the button
    /// stops being disabled as soon as the filter is live.
    private func refreshNoiseButton() {
        let available = playbackService.noiseReductionAvailable
        let enabled = playbackService.noiseReductionEnabled
        noiseButton.isEnabled = available
        noiseButton.configuration?.baseForegroundColor = enabled ? DiscourseColors.current.accent : .white
        noiseButton.accessibilityValue = enabled ? "On" : "Off"
    }

    private func setupDiscourseLikeButton() {
        _ = Self.clipCleanup
        NotificationCenter.default.addObserver(self, selector: #selector(clipEnteredBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        noiseButton.accessibilityIdentifier = "noiseReduction"
        noiseButton.accessibilityLabel = NSLocalizedString("NOISE_REDUCTION", comment: "")
        discourseLikeButton.contentHorizontalAlignment = .center
        audioPlayerView.actionStackView.addArrangedSubview(discourseLikeButton)
        clipButton.accessibilityLabel = NSLocalizedString("CLIP_BUTTON", comment: "")
        clipButton.accessibilityIdentifier = "discourseClip"
        audioPlayerView.actionStackView.addArrangedSubview(clipButton)
        mediaNavigationBar.insertArrangedSubview(discourseButton, at: mediaNavigationBar.arrangedSubviews.firstIndex(of: mediaNavigationBar.queueButton) ?? 0)
        mediaNavigationBar.insertArrangedSubview(playlistButton, at: mediaNavigationBar.arrangedSubviews.firstIndex(of: discourseButton) ?? 0)
        playlistButton.accessibilityLabel = NSLocalizedString("ADD_TO_PLAYLIST", comment: "")
        playlistButton.accessibilityIdentifier = "discoursePlayerPlaylist"
        playlistButton.widthAnchor.constraint(equalTo: mediaNavigationBar.heightAnchor).isActive = true
        discourseButton.accessibilityLabel = NSLocalizedString("DISCOURSE", comment: "")
        discourseButton.widthAnchor.constraint(equalTo: mediaNavigationBar.heightAnchor).isActive = true
        playerDownloadControl.accessibilityIdentifier = "discoursePlayerDownload"
        playerDownloadControl.addTarget(self, action: #selector(togglePlayerDownload), for: .touchUpInside)
        audioPlayerView.actionStackView.addArrangedSubview(playerDownloadControl)
        audioPlayerView.actionStackView.addArrangedSubview(noiseButton)
        NSLayoutConstraint.activate([
            discourseLikeButton.widthAnchor.constraint(equalTo: audioPlayerView.actionStackView.widthAnchor,
                                                       multiplier: 0.25)
        ])

        let center = NotificationCenter.default
        for name in [VLCPlaybackServiceNoiseReductionDidChange,
                     VLCPlaybackServicePlaybackDidStart,
                     VLCPlaybackServicePlaybackDidMoveOnToNextItem,
                     VLCPlaybackServicePlaybackWillStop,
                     VLCPlaybackServicePlaybackDidStop,
                     VLCPlaybackServicePlaybackDidFail] {
            center.addObserver(self,
                               selector: #selector(updateDiscourseLike),
                               name: Notification.Name(name),
                               object: nil)
        }
        center.addObserver(self,
                           selector: #selector(updateDiscourseLike),
                           name: .discourseDownloadsDidChange,
                           object: nil)
        center.addObserver(self,
                           selector: #selector(updateDiscourseLike),
                           name: .discourseLikesDidChange,
                           object: nil)
        center.addObserver(self,
                           selector: #selector(updateDiscourseLike),
                           name: .VLCThemeDidChangeNotification,
                           object: nil)
        updateDiscourseLike()
    }

    @objc private func updateDiscourseLike() {
        clipButton.setNeedsUpdateConfiguration()
        discourseButton.isEnabled = currentDiscourseIdentity().map { !$0.discourseID.isEmpty } ?? false
        clipButton.isEnabled = currentDiscourseTrack() != nil && playbackService.isSeekable && playbackService.mediaDuration >= 1000
        if let audioID = clipTrackID,
           currentDiscourseTrack()?.id != audioID || DiscourseDownloadStore.shared.localURL(for: audioID) == nil {
            endClipEditing()
        }
        refreshPlayerDownload()
        refreshNoiseButton()
        guard let track = currentDiscourseTrack() else {
            discourseLikeButton.isHidden = true
            return
        }
        discourseLikeButton.configure(with: DiscourseLikeState.resolve(target: .audio(track.id),
                                                                        payloadLikes: track.totalLikes),
                                      title: track.title)
        discourseLikeButton.isHidden = false
    }

    @objc private func toggleDiscourseLike() {
        guard let track = currentDiscourseTrack() else {
            return
        }
        DiscourseLikeActions.toggleAudio(track, from: self)
    }

    private func currentDiscourseTrack() -> DiscourseAudio? {
        guard let identity = currentDiscourseIdentity() else {
            return nil
        }
        return DiscourseTrackRegistry.shared.track(id: identity.audioID)
    }

    private func currentDiscourseIdentity() -> DiscourseMediaIdentity? {
        guard let media = playbackService.currentlyPlayingMedia else { return nil }
        return DiscourseMediaFactory.identity(of: media)
    }
#endif

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.isHidden = true
        playbackService.delegate = self
        playbackService.recoverPlaybackState()
        audioPlayerView.updateThumbnailImageView()
        audioPlayerView.setupBackgroundColor()
        refreshPlaybackSpeed()
        mediaScrubProgressBar.updateInterfacePosition()
        playModeUpdated()

        if playbackService.isPlayingOnExternalScreen() {
            changeOutputView(to: externalOutputView.displayView)
        }

        let isLandscape = view.bounds.width > view.bounds.height
        audioPlayerView.updateLayout(isLandscape: isLandscape)
        mediaScrubProgressBar.shouldHideScrubLabels = isLandscape
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        audioPlayerView.resetCornerRadius()
    }

    override func viewWillDisappear(_ animated: Bool) {
#if os(iOS)
        if presentedViewController == nil { endClipEditing() }
#endif
        if playerController.isInterfaceLocked {
            setPlayerInterfaceEnabled(true)
        }
        queueViewController?.hide()
        numberOfGestureSeek = 0
        totalSeekDuration = 0
        previousSeekState = .default
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        let isLandscape = size.width > size.height
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.audioPlayerView.updateLayout(isLandscape: isLandscape)
            self?.mediaScrubProgressBar.shouldHideScrubLabels = isLandscape
        })
    }

    // MARK: Public methods

    override func minimizePlayer() {
        delegate?.audioPlayerViewControllerDidMinimize(self)
    }

    override var resetsPositionOnMinimize: Bool {
        return true
    }
    
    override func updatePlaybackSpeedIcon() {
        super.updatePlaybackSpeedIcon()
        refreshPlaybackSpeed()
    }

    private func refreshPlaybackSpeed() {
        let playbackSpeed = playbackService.playbackRate
        audioPlayerView.updatePlaybackSpeedButton(with: playbackSpeed)
        audioPlayerView.shouldDisplaySecondaryStackView(abs(playbackSpeed - 1) > 0.001)
    }

    @objc func setupQueueViewController(with qvc: QueueViewController) {
        queueViewController = qvc
        queueViewController?.delegate = nil
    }

    @objc func handleMoreOptionsButton() {
        present(moreOptionsActionSheet, animated: false) {
            [unowned self] in
            self.moreOptionsActionSheet.interfaceDisabled = self.playerController.isInterfaceLocked
        }
    }

    private var artworkTransitionInProgress = false
    private var artworkPanIsHorizontal = false

    // Zero means spring back; the sign is the direction the artwork leaves.
    static func artworkSwipeDirection(translation: CGFloat, velocity: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        if abs(translation) >= width * 0.25 {
            return translation < 0 ? -1 : 1
        }
        if abs(velocity) > 500 && translation * velocity > 0 {
            return velocity < 0 ? -1 : 1
        }
        return 0
    }

    @objc override func handlePanGesture(recognizer: UIPanGestureRecognizer) {
        if recognizer.state == .began {
            let velocity = recognizer.velocity(in: view)
            artworkPanIsHorizontal = abs(velocity.x) > abs(velocity.y)
        }
        guard artworkPanIsHorizontal else {
            super.handlePanGesture(recognizer: recognizer)
            return
        }
        let artwork = audioPlayerView.thumbnailImageView
        let translation = recognizer.translation(in: audioPlayerView.thumbnailView).x
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        switch recognizer.state {
        case .began, .changed:
            if !reduceMotion {
                artwork.transform = CGAffineTransform(translationX: translation, y: 0)
            }
        case .ended, .cancelled, .failed:
            let direction = recognizer.state == .ended ? Self.artworkSwipeDirection(
                translation: translation, velocity: recognizer.velocity(in: view).x,
                width: artwork.bounds.width) : 0
            let queue = playbackService.isShuffleMode ? playbackService.shuffledList : playbackService.mediaList
            let index = playbackService.currentlyPlayingMedia.map { Int(queue.index(of: $0)) } ?? NSNotFound
            let count = Int(queue.count)
            let canSwitch = count > 1 && index != NSNotFound &&
                (playbackService.repeatMode == .repeatAllItems ||
                 (direction < 0 ? index + 1 < count : index > 0 || playbackService.playedTime().intValue >= 2000))
            artworkTransitionInProgress = true
            guard direction != 0 && canSwitch else {
                UIView.animate(withDuration: reduceMotion ? 0 : 0.2, animations: {
                    artwork.transform = .identity
                }, completion: { _ in self.artworkTransitionInProgress = false })
                return
            }
            // Freeze the outgoing cover so asynchronous metadata cannot replace it mid-slide.
            let outgoing = artwork.snapshotView(afterScreenUpdates: false)
            outgoing?.frame = artwork.frame
            if let outgoing = outgoing {
                artwork.superview?.addSubview(outgoing)
            }
            let restartsCurrent = direction > 0 && playbackService.playedTime().intValue >= 2000
            artwork.setImage(nil, placeholderName: playbackService.metadata.placeholderName)
            audioPlayerView.setupBackgroundColor()
            if direction < 0 {
                playbackService.next()
            } else {
                playbackService.previous()
            }
            if restartsCurrent {
                audioPlayerView.updateThumbnailImageView()
                audioPlayerView.setupBackgroundColor()
            }
            artwork.transform = reduceMotion ? .identity :
                CGAffineTransform(translationX: -direction * view.bounds.width, y: 0)
            UIView.animate(withDuration: reduceMotion ? 0 : 0.25, animations: {
                outgoing?.transform = CGAffineTransform(translationX: direction * self.view.bounds.width, y: 0)
                artwork.transform = .identity
            }, completion: { _ in
                outgoing?.removeFromSuperview()
                self.artworkTransitionInProgress = false
            })
        default:
            break
        }
    }

    override func setupGestures() {
        super.setupGestures()

        audioPlayerView.thumbnailView.addGestureRecognizer(panRecognizer)
        audioPlayerView.thumbnailView.addGestureRecognizer(doubleTapGestureRecognizer)
        audioPlayerView.addGestureRecognizer(playPauseRecognizer)
        audioPlayerView.addGestureRecognizer(pinchRecognizer)
        
        panRecognizer.delegate = self
    }

    @objc override func handlePinchGesture(recognizer: UIPinchGestureRecognizer) {
        if recognizer.velocity < 0 && playerController.isCloseGestureEnabled {
            delegate?.audioPlayerViewControllerDidMinimize(self)
        }
    }

#if os(iOS)
    override func changeOutputView(to output: UIView?) {
        guard output == externalOutputView.displayView else {
            externalOutputView.isHidden = true
            audioPlayerView.thumbnailView.isHidden = false
            return
        }

        if let renderer = playbackService.renderer {
            externalOutputView.updateUI(rendererName: renderer.name, title: nil)
            externalOutputView.isHidden = false
            audioPlayerView.thumbnailView.isHidden = true
        }
    }
#endif

    override func handleDoubleTapGesture(_ sender: UITapGestureRecognizer) {
        let screenWidth: CGFloat = view.frame.size.width
        let middleBoundary: CGFloat = screenWidth / 2.0

        let tapPosition = sender.location(in: view)

        // Reset number(set to -1/1) of seek when orientation has been changed.
        if tapPosition.x < middleBoundary {
            numberOfGestureSeek = previousSeekState == .forward ? -1 : numberOfGestureSeek - 1
        } else {
            numberOfGestureSeek = previousSeekState == .backward ? 1 : numberOfGestureSeek + 1
        }

        super.handleDoubleTapGesture(sender)
    }

    override func applyCornerRadius() {
        super.applyCornerRadius()

        audioPlayerView.applyCornerRadius()
    }

    override func resetCornerRadius() {
        super.resetCornerRadius()

        audioPlayerView.resetCornerRadius()
    }

    // MARK: - Private methods

    private func setupAudioPlayerViewConstraints() {
        audioPlayerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(audioPlayerView)

        NSLayoutConstraint.activate([
            audioPlayerView.topAnchor.constraint(equalTo: view.topAnchor),
            audioPlayerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            audioPlayerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            audioPlayerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupOptionsNavigationBar() {
        let padding: CGFloat = 10.0

        view.addSubview(optionsNavigationBar)
        NSLayoutConstraint.activate([
            optionsNavigationBar.topAnchor.constraint(equalTo: audioPlayerView.navigationBarView.bottomAnchor, constant: padding),
            optionsNavigationBar.trailingAnchor.constraint(equalTo: audioPlayerView.safeAreaLayoutGuide.trailingAnchor, constant: -padding)
        ])
    }

#if os(iOS)
    private func setupSliders() {
        audioPlayerView.setupSliders(with: brightnessControlView, and: volumeControlView)

        NSLayoutConstraint.activate([
            brightnessControlView.topAnchor.constraint(greaterThanOrEqualTo: optionsNavigationBar.bottomAnchor),
            volumeControlView.topAnchor.constraint(greaterThanOrEqualTo: optionsNavigationBar.bottomAnchor)
        ])
    }
#endif

    private func setupStatusLabel() {
        audioPlayerView.addSubview(statusLabel)
        audioPlayerView.bringSubviewToFront(statusLabel)

        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: audioPlayerView.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: audioPlayerView.centerYAnchor)
        ])
    }

    private func setupLoadingIndicator() {
        audioPlayerView.addSubview(loadingIndicator)
        audioPlayerView.bringSubviewToFront(loadingIndicator)

        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: audioPlayerView.thumbnailImageView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: audioPlayerView.thumbnailImageView.centerYAnchor)
        ])
    }

    private func showPlayqueue(from qvc: QueueViewController) {
        qvc.view.removeFromSuperview()
        qvc.removeFromParent()
        qvc.show()
        qvc.topView.isHidden = true
        addChild(qvc)
        qvc.didMove(toParent: self)
        view.layoutIfNeeded()
        qvc.bottomConstraint?.constant = 0
        UIView.animate(withDuration: 0.3, animations: {
            self.view.layoutIfNeeded()
        })
        qvc.delegate = nil
    }

    private func updateNavigationBar(with title: String?) {
        mediaNavigationBar.setMediaTitleLabelText(title)
        updateFavoriteButton()
    }

    private func setPlayerInterfaceEnabled(_ enabled: Bool) {
        mediaNavigationBar.closePlaybackButton.isEnabled = enabled
        mediaNavigationBar.favoriteButton.isEnabled = enabled
        mediaNavigationBar.queueButton.isEnabled = enabled
#if os(iOS)
        mediaNavigationBar.deviceButton.isEnabled = enabled
        mediaNavigationBar.airplayRoutePickerView.isUserInteractionEnabled = enabled
        mediaNavigationBar.airplayRoutePickerView.alpha = !enabled ? 0.5 : 1
#else
        mediaNavigationBar.airplayVolumeView.isUserInteractionEnabled = enabled
        mediaNavigationBar.airplayVolumeView.alpha = !enabled ? 0.5 : 1
#endif

        mediaScrubProgressBar.progressSlider.isEnabled = enabled
        mediaScrubProgressBar.remainingTimeButton.isEnabled = enabled

        audioPlayerView.setControlsEnabled(enabled)

        shouldDisableGestures(!enabled)
        minimizeGestureRecognizer.isEnabled = enabled

        playerController.isInterfaceLocked = !enabled
    }

    @objc override func updatePlayerControls() {
        audioPlayerView.shouldEnableSeekButtons(true)
    }
}

// MARK: - AudioPlayerViewDelegate

extension AudioPlayerViewController: AudioPlayerViewDelegate {
    func audioPlayerViewDelegateGetThumbnail(_ audioPlayerView: AudioPlayerView) -> UIImage? {
        return playbackService.metadata.artworkImage
    }

    func audioPlayerViewDelegateGetPlaceholderName(_ audioPlayerView: AudioPlayerView) -> String? {
        return playbackService.metadata.placeholderName
    }

    func audioPlayerViewDelegateDidTapShuffleButton(_ audioPlayerView: AudioPlayerView) {
        updateShuffleState()
    }

    func audioPlayerViewDelegateDidTapBackwardButton(_ audioPlayerView: AudioPlayerView) {
        totalSeekDuration = previousSeekState == .forward ? -30 : totalSeekDuration - 30
        previousSeekState = .backward

        displayAndApplySeekDuration(30)
    }

    func audioPlayerViewDelegateDidTapPreviousButton(_ audioPlayerView: AudioPlayerView) {
        playbackService.previous()
    }

    func audioPlayerViewDelegateDidTapPlayButton(_ audioPlayerView: AudioPlayerView) {
#if os(iOS)
        if let editor = clipEditor, !playbackService.isPlaying {
            clipPausedAtEnd = false
            let start = clipPreview.pendingStart ?? editor.range.start
            clipPreview.requestStart(at: start)
            editor.setPosition(start)
        }
#endif
        playbackService.playPause()
        audioPlayerView.updatePlayButton(isPlaying: playbackService.isPlaying)
    }

    func audioPlayerViewDelegateDidTapNextButton(_ audioPlayerView: AudioPlayerView) {
        playbackService.next()
    }

    func audioPlayerViewDelegateDidTapForwardButton(_ audioPlayerView: AudioPlayerView) {
        totalSeekDuration = previousSeekState == .backward ? 30 : totalSeekDuration + 30
        previousSeekState = .forward

        displayAndApplySeekDuration(30)
    }

    func audioPlayerViewDelegateDidTapRepeatButton(_ audioPlayerView: AudioPlayerView) {
        updateRepeatMode()
    }

    func audioPlayerViewDelegateDidTapPlaybackSpeedButton(_ audioPlayerView: AudioPlayerView) {
        showPlaybackSpeedCard()
    }

    func audioPlayerViewDelegateDidLongPressPlaybackSpeedButton(_ audioPlayerView: AudioPlayerView) {
        let speedManager = PlaybackSpeedCustomManager.shared
        playbackService.playbackRate = 1
        if speedManager.appliesToAllMedia {
            speedManager.setDefaultSpeed(1)
        }
        updatePlaybackSpeedIcon()
    }

}

// MARK: - VLCPlaybackServiceDelegate

extension AudioPlayerViewController {
    func prepare(forMediaPlayback playbackService: PlaybackService) {
        audioPlayerView.updatePlayButton(isPlaying: playbackService.isPlaying)
        audioPlayerView.updateShuffleRepeatState(shuffleEnabled: playbackService.isShuffleMode, repeatMode: playbackService.repeatMode)

        let metadata = playbackService.metadata
        audioPlayerView.updateLabels(title: metadata.title, artist: metadata.artist, album: metadata.albumName, isQueueHidden: isQueueHidden)
        updateNavigationBar(with: isQueueHidden ? nil : metadata.title)
        mediaScrubProgressBar.updateLiveStreamState()

        if let qvc = queueViewController, !isQueueHidden {
            showPlayqueue(from: qvc)
        }

        audioPlayerView.thumbnailView.isHidden = playbackService.isPlayingOnExternalScreen()
#if os(iOS)
        updateDiscourseLike()
#endif
    }

    override func playbackPositionUpdated(_ playbackService: PlaybackService) {
        super.playbackPositionUpdated(playbackService)
#if os(iOS)
        refreshNoiseButton()
        clipButton.isEnabled = currentDiscourseTrack() != nil && playbackService.isSeekable && playbackService.mediaDuration >= 1000
        updateClipPreview()
#endif
    }

    override func mediaPlayerStateChanged(_ currentState: VLCMediaPlayerState,
                                 isPlaying: Bool,
                                 currentMediaHasTrackToChooseFrom: Bool, currentMediaHasChapters: Bool,
                                 for playbackService: PlaybackService) {
        super.mediaPlayerStateChanged(currentState, isPlaying: isPlaying,
                                      currentMediaHasTrackToChooseFrom: currentMediaHasTrackToChooseFrom,
                                      currentMediaHasChapters: currentMediaHasChapters,
                                      for: playbackService)
#if os(iOS)
        refreshNoiseButton()
#endif

        audioPlayerView.updatePlayButton(isPlaying: isPlaying)
        audioPlayerView.shouldEnableSeekButtons(true)

        let image: UIImage? = isPlaying ? UIImage(named: "minimize") : UIImage(named: "close")
        let accessibilityLabel: String = isPlaying ? NSLocalizedString("MINIMIZE_BUTTON", comment: "") : NSLocalizedString("STOP_BUTTON", comment: "")
        let accessibilityHint: String = isPlaying ? NSLocalizedString("MINIMIZE_HINT", comment: "") : NSLocalizedString("CLOSE_HINT", comment: "")
        mediaNavigationBar.updateCloseButton(with: image, accessibility: (accessibilityLabel, accessibilityHint))

        if currentState == .opening && playbackService.numberOfVideoTracks > 0 {
            // This media contains video tracks and can be played with the Video Player.
            delegate?.audioPlayerViewControllerShouldSwitchPlayer(self)
            return
        }

        if let queueCollectionView = queueViewController?.queueCollectionView {
            queueCollectionView.reloadData()
        }

        if currentState == .error {
            statusLabel.showStatusMessage(NSLocalizedString("PLAYBACK_FAILED",
                                                            comment: ""))
        }

        if currentState == .opening || currentState == .stopped {
            resetABRepeat()
        }

        moreOptionsActionSheet.currentMediaHasChapters = currentMediaHasChapters
    }

    func displayMetadata(for playbackService: PlaybackService, metadata: VLCMetaData) {
        audioPlayerView.updateLabels(title: metadata.title, artist: metadata.artist, album: metadata.albumName, isQueueHidden: isQueueHidden)
        updateNavigationBar(with: isQueueHidden ? nil : metadata.title)
        mediaScrubProgressBar.updateLiveStreamState()

        if metadata.artworkImage != audioPlayerView.thumbnailImageView.image
            || metadata.placeholderName != audioPlayerView.thumbnailImageView.placeholderName {
            audioPlayerView.updateThumbnailImageView()
            audioPlayerView.setupBackgroundColor()
        }
    }

    func playModeUpdated() {
        audioPlayerView.updateShuffleRepeatState(shuffleEnabled: playbackService.isShuffleMode, repeatMode: playbackService.repeatMode)
    }

#if os(iOS)
    func updateWidgetsIfNeeded() {
        let widgetCenter = WidgetCenter.shared
        widgetCenter.getCurrentConfigurations({ result in
            switch result {
            case let .success(widgetInfo):
                if !widgetInfo.isEmpty {
                    widgetCenter.reloadAllTimelines()
                }
            case let .failure(error):
                assertionFailure("AudioPlayerViewController: \(error)")
            }
        })
    }
#endif
}

// MARK: - PlayerControllerDelegate

extension AudioPlayerViewController: PlayerControllerDelegate {
    func playerControllerExternalScreenDidConnect(_ playerController: PlayerController) {
        // TODO
    }

    func playerControllerExternalScreenDidDisconnect(_ playerController: PlayerController) {
        // TODO
    }

    func playerControllerApplicationBecameActive(_ playerController: PlayerController) {
        // TODO
    }
}

// MARK: - MediaNavigationBarDelegate

extension AudioPlayerViewController {
    override func mediaNavigationBarDidTapClose(_ mediaNavigationBar: MediaNavigationBar) {
        if playbackService.isPlaying {
            delegate?.audioPlayerViewControllerDidMinimize(self)
        } else {
            playbackService.stopPlayback()
            self.dismiss(animated: true)
            isQueueHidden = true
        }
    }

    func mediaNavigationBarDidToggleQueueView(_ mediaNavigationBar: MediaNavigationBar) {
        let metadata = playbackService.metadata
        audioPlayerView.updateLabels(title: metadata.title, artist: metadata.artist, album: metadata.albumName, isQueueHidden: !isQueueHidden)
        updateNavigationBar(with: !isQueueHidden ? nil : metadata.title)

        audioPlayerView.thumbnailView.isHidden = playbackService.isPlayingOnExternalScreen()
        audioPlayerView.playqueueView.isHidden = !isQueueHidden

        if let qvc = queueViewController, isQueueHidden {
            showPlayqueue(from: qvc)
        } else if let qvc = queueViewController, !isQueueHidden {
            qvc.dismissFromAudioPlayer()
        }

        shouldDisableGestures(isQueueHidden)

        isQueueHidden = !isQueueHidden
    }

    override func mediaNavigationBarDidCloseLongPress(_ mediaNavigationBar: MediaNavigationBar) {
        super.mediaNavigationBarDidCloseLongPress(mediaNavigationBar)
        isQueueHidden = true
    }

    func mediaNavigationBarDisplayCloseAlert(_ mediaNavigationBar: MediaNavigationBar) {
        statusLabel.showStatusMessage(NSLocalizedString("CLOSE_HINT", comment: ""))
    }
}

// MARK: - MediaMoreOptionsActionSheetDelegate

extension AudioPlayerViewController {
    override func mediaMoreOptionsActionSheetDidToggleInterfaceLock(state: Bool) {
        super.mediaMoreOptionsActionSheetDidToggleInterfaceLock(state: state)

        setPlayerInterfaceEnabled(!state)
    }

    override func mediaMoreOptionsActionSheetDisplayAddBookmarksView(_ bookmarksView: AddBookmarksView) {
        super.mediaMoreOptionsActionSheetDisplayAddBookmarksView(bookmarksView)

        if let bookmarksView = addBookmarksView {
            view.addSubview(bookmarksView)
            NSLayoutConstraint.activate([
                bookmarksView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                bookmarksView.leadingAnchor.constraint(equalTo: audioPlayerView.safeAreaLayoutGuide.leadingAnchor),
                bookmarksView.trailingAnchor.constraint(equalTo: audioPlayerView.safeAreaLayoutGuide.trailingAnchor),
                bookmarksView.topAnchor.constraint(equalTo: audioPlayerView.safeAreaLayoutGuide.topAnchor, constant: 16),
                bookmarksView.bottomAnchor.constraint(equalTo: audioPlayerView.controlsStackView.topAnchor),
            ])
        }

        audioPlayerView.shouldDisableControls(true)
    }

    override func mediaMoreOptionsActionSheetRemoveAddBookmarksView() {
        super.mediaMoreOptionsActionSheetRemoveAddBookmarksView()

        audioPlayerView.shouldDisableControls(false)
    }

    override func mediaMoreOptionsActionSheetPresentABRepeatView(with abView: ABRepeatView) {
        super.mediaMoreOptionsActionSheetPresentABRepeatView(with: abView)

        guard let abRepeatView = abRepeatView else {
            return
        }

        audioPlayerView.addSubview(abRepeatView)
        audioPlayerView.bringSubviewToFront(abRepeatView)
        abRepeatView.isUserInteractionEnabled = true
        NSLayoutConstraint.activate([
            abRepeatView.centerXAnchor.constraint(equalTo: audioPlayerView.safeAreaLayoutGuide.centerXAnchor),
            abRepeatView.bottomAnchor.constraint(equalTo: mediaScrubProgressBar.topAnchor, constant: -10.0),
        ])
    }

    func mediaMoreOptionsActionSheetCanShareCurrentTrack() -> Bool {
        return shareURLForCurrentTrack() != nil
    }

    func mediaMoreOptionsActionSheetShareCurrentTrack() {
        guard let url = shareURLForCurrentTrack() else {
            return
        }

        let activityViewController = UIActivityViewController(activityItems: [url],
                                                              applicationActivities: nil)
        activityViewController.popoverPresentationController?.sourceView = moreOptionsButton
        activityViewController.popoverPresentationController?.sourceRect = moreOptionsButton.bounds
        present(activityViewController, animated: true)
    }

    private func shareURLForCurrentTrack() -> URL? {
        guard let identity = DiscoursePlayback.shared.currentIdentity() else {
            return nil
        }
        return DiscourseDeepLink.trackURL(discourseID: identity.discourseID,
                                          audioID: identity.audioID)
    }
}

// MARK: - ZoomTransitionEndpoint

extension AudioPlayerViewController: ZoomTransitionEndpoint {
    var zoomTransitionArtworkView: VLCArtworkImageView? {
        return audioPlayerView.thumbnailImageView
    }
}

// MARK: - UIGestureRecognizerDelegate

extension AudioPlayerViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer == panRecognizer else { return true }
        return !artworkTransitionInProgress && !playerController.isInterfaceLocked &&
            !mediaScrubProgressBar.isScrubbing
    }
}
