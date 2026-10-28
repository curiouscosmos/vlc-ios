/*****************************************************************************
 * DiscourseAudioMixer.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * The Audio Mixer engine (AGENTS.md section 6.7): a second `VLCMediaPlayer`
 * that plays one explicitly added local file alongside the main player. It
 * follows the main player (start ~250 ms after it starts, pause with it, stop
 * when it stops or when a video starts), loops the track when asked, fades in
 * and out, and keeps its own volume that the main player can never change. The
 * mixer is gated by its persisted switch, so it only ever plays what the user
 * added and enabled.
 *****************************************************************************/

import AVFoundation
import Foundation

final class DiscourseAudioMixer: NSObject {
    static let shared = DiscourseAudioMixer()

    static let filesKey = "audio_mixer_files"
    static let selectedKey = "audio_mixer_selected"
    static let enabledKey = "audio_mixer_enabled"
    static let loopKey = "audio_mixer_loop"
    static let volumeKey = "audio_mixer_volume"
    static let defaultVolume = 50
    static let minimumVolume = 1
    static let maximumVolume = 100

    /// How long after the main player starts the mixer joins in.
    private static let joinDelay: TimeInterval = 0.25
    private static let fadeInDuration: TimeInterval = 0.2
    private static let fadeOutDuration: TimeInterval = 0.22
    private static let fadeSteps = 5

    private let settings: DiscourseSettings
    private let notificationCenter: NotificationCenter
    private let playback: PlaybackService
    private let fileImporter: DiscourseMixerFileImporter

    /// Persisted membership, in the user's order.
    private var storedURLs: [String]
    private var storedSelection: String?

    private var player: VLCMediaPlayer?
    private var loadedURL: URL?
    /// A stop finished, so the next play must build a fresh item.
    private var needsReload = false
    /// The last stop was requested by us, not the end of the track.
    private var isStopping = false
    private var fadeTimer: Timer?
    private var pendingStart: DispatchWorkItem?

    private(set) var isPlaying = false

    // MARK: - Persisted settings

    /// Whether the mixer follows the main player. Default off (AGENTS 6.7).
    private(set) var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            settings.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled {
                scheduleStart()
            } else {
                pause()
            }
            notifyChange()
        }
    }

    /// Whether one track restarts when it ends. Default on.
    private(set) var isLooping: Bool {
        didSet {
            guard isLooping != oldValue else { return }
            settings.set(isLooping, forKey: Self.loopKey)
            if isPlaying {
                // Reloading the item applies the new end-of-track rule.
                restart(resetVolume: true)
            }
            notifyChange()
        }
    }

    /// Mixer volume, 1…100. Never follows the main player (AGENTS 6.7).
    private(set) var volume: Int {
        didSet {
            let clamped = min(Self.maximumVolume, max(Self.minimumVolume, volume))
            if clamped != volume {
                volume = clamped
                return
            }
            guard volume != oldValue else { return }
            settings.set(volume, forKey: Self.volumeKey)
            cancelFade()
            applyVolume(volume)
            notifyChange()
        }
    }

    // MARK: - Lifecycle

    init(settings: DiscourseSettings = .shared,
         notificationCenter: NotificationCenter = .default,
         playback: PlaybackService = PlaybackService.sharedInstance(),
         fileImporter: DiscourseMixerFileImporter = DiscourseMixerFileImporter()) {
        self.settings = settings
        self.notificationCenter = notificationCenter
        self.playback = playback
        self.fileImporter = fileImporter
        storedURLs = (settings.decode([String].self, forKey: Self.filesKey) ?? [])
            .filter { URL(string: $0) != nil }
        storedSelection = settings.string(Self.selectedKey)
        isEnabled = settings.bool(Self.enabledKey)
        isLooping = settings.contains(Self.loopKey) ? settings.bool(Self.loopKey) : true
        let storedVolume = settings.int(Self.volumeKey) ?? Self.defaultVolume
        volume = min(Self.maximumVolume, max(Self.minimumVolume, storedVolume))

        super.init()

        addObservers()
    }

    // MARK: - Membership

    /// The mixer's files in order.
    var items: [URL] {
        return storedURLs.compactMap { URL(string: $0) }
    }

    var selectedURL: URL? {
        if let storedSelection,
           let url = URL(string: storedSelection),
           items.contains(url) {
            return url
        }
        return items.first
    }

    var selectedIndex: Int? {
        guard let selectedURL else {
            return nil
        }
        return items.firstIndex(of: selectedURL)
    }

    /// Adds a local file once. Returns `false` for duplicates or non-file URLs.
    @discardableResult
    func add(_ url: URL) -> Bool {
        let normalized = url.standardizedFileURL
        guard normalized.isFileURL,
              !items.contains(where: { $0.standardizedFileURL == normalized }) else {
            return false
        }

        storedURLs.append(normalized.absoluteString)
        if storedSelection == nil {
            storedSelection = normalized.absoluteString
        }
        persistMembership()
        notifyChange()
        return true
    }

    func remove(at index: Int) {
        let current = items
        guard current.indices.contains(index) else {
            return
        }
        let url = current[index]
        let wasSelected = url == selectedURL
        storedURLs.remove(at: index)
        if wasSelected {
            stop(reason: .removed)
            storedSelection = items.first?.absoluteString
        }
        fileImporter.removeImportedFile(at: url)
        persistMembership()
        notifyChange()
    }

    func move(from source: Int, to destination: Int) {
        guard items.indices.contains(source), source != destination else {
            return
        }
        var list = storedURLs
        let value = list.remove(at: source)
        let target = min(max(destination, 0), list.count)
        list.insert(value, at: target)
        storedURLs = list
        persistMembership()
        notifyChange()
    }

    func clear() {
        guard !storedURLs.isEmpty else {
            return
        }
        let removedURLs = items
        stop(reason: .removed)
        storedURLs = []
        storedSelection = nil
        removedURLs.forEach { fileImporter.removeImportedFile(at: $0) }
        persistMembership()
        notifyChange()
    }

    /// Makes `url` the track the mixer plays. Restarts it when the mixer is
    /// already playing so the new selection is audible immediately.
    func select(_ url: URL) {
        guard items.contains(url) else {
            return
        }
        storedSelection = url.absoluteString
        persistMembership()
        if isPlaying {
            restart(resetVolume: true)
        }
        notifyChange()
    }

    // MARK: - Controls

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    func setLooping(_ looping: Bool) {
        isLooping = looping
    }

    func setVolume(_ value: Int) {
        volume = value
    }

    /// Arms the mixer when the main player is idle; otherwise toggles playback.
    func togglePlayback() {
        if isPlaying {
            pause()
            return
        }
        if !isEnabled {
            isEnabled = true
        }
        play()
    }

    /// A track is deleted, the mixer is switched off or the main player stopped.
    private enum StopReason {
        case removed
        case followed
    }

    private func play() {
        guard playback.isPlaying,
              playback.numberOfVideoTracks == 0 || playback.playAsAudio,
              let url = selectedURL else {
            return
        }
        pendingStart?.cancel()
        pendingStart = nil
        ensureLoaded(url)
        isStopping = false
        isPlaying = true
        player?.play()
        applyVolume(0)
        fade(to: volume)
        notifyChange()
    }

    private func pause() {
        pendingStart?.cancel()
        pendingStart = nil
        guard isPlaying else {
            return
        }
        isPlaying = false
        fadeOut { [weak self] in
            guard let self, !self.isPlaying else { return }
            self.player?.pause()
        }
        notifyChange()
    }

    private func stop(reason: StopReason) {
        pendingStart?.cancel()
        pendingStart = nil
        guard player != nil else {
            isPlaying = false
            return
        }
        isPlaying = false
        isStopping = true
        fadeOut { [weak self] in
            guard let self else { return }
            self.player?.stop()
            self.needsReload = true
        }
        notifyChange()
    }

    /// Reloads the current selection, used by loop changes and selection
    /// changes while playing.
    private func restart(resetVolume: Bool) {
        guard playback.isPlaying,
              playback.numberOfVideoTracks == 0 || playback.playAsAudio,
              let url = selectedURL else {
            return
        }
        ensureLoaded(url, force: true)
        isStopping = false
        isPlaying = true
        player?.play()
        if resetVolume {
            applyVolume(0)
            fade(to: volume)
        } else {
            applyVolume(volume)
        }
        notifyChange()
    }

    // MARK: - Persistence

    private func persistMembership() {
        settings.encode(storedURLs, forKey: Self.filesKey)
        settings.set(storedSelection, forKey: Self.selectedKey)
    }

    // MARK: - Player

    private func ensureLoaded(_ url: URL, force: Bool = false) {
        if !force, player != nil, loadedURL == url, !needsReload {
            return
        }
        player?.delegate = nil
        player?.stop()

        let media = VLCMedia(url: url)
        let newPlayer = VLCMediaPlayer()
        newPlayer.delegate = self
        newPlayer.media = media
        player = newPlayer
        loadedURL = url
        needsReload = false
    }

    private func applyVolume(_ value: Int) {
        player?.audio?.volume = Int32(min(200, max(0, value)))
    }

    // MARK: - Fades

    private func fade(to target: Int) {
        let start = Int(player?.audio?.volume ?? 0)
        runFade(from: start, to: target, duration: Self.fadeInDuration, completion: nil)
    }

    private func fadeOut(completion: @escaping () -> Void) {
        let start = Int(player?.audio?.volume ?? 0)
        runFade(from: start, to: 0, duration: Self.fadeOutDuration, completion: completion)
    }

    private func runFade(from: Int,
                         to: Int,
                         duration: TimeInterval,
                         completion: (() -> Void)?) {
        cancelFade()
        guard player != nil else {
            completion?()
            return
        }
        let steps = Self.fadeSteps
        let interval = duration / Double(steps)
        var step = 0
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            step += 1
            let progress = Double(step) / Double(steps)
            let value = Int((Double(from) + (Double(to - from) * progress)).rounded())
            self.applyVolume(value)
            if step >= steps {
                timer.invalidate()
                self.fadeTimer = nil
                completion?()
            }
        }
        fadeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func cancelFade() {
        fadeTimer?.invalidate()
        fadeTimer = nil
    }

    // MARK: - Following the main player

    private func addObservers() {
        let center = notificationCenter
        let names: [(Notification.Name, Selector)] = [
            (Notification.Name(VLCPlaybackServicePlaybackDidStart), #selector(mainPlaybackStarted)),
            (Notification.Name(VLCPlaybackServicePlaybackDidResume), #selector(mainPlaybackStarted)),
            (Notification.Name(VLCPlaybackServicePlaybackDidPause), #selector(mainPlaybackPaused)),
            (Notification.Name(VLCPlaybackServicePlaybackWillStop), #selector(mainPlaybackStopped)),
            (Notification.Name(VLCPlaybackServicePlaybackDidStop), #selector(mainPlaybackStopped)),
            (Notification.Name(VLCPlaybackServicePlaybackDidFail), #selector(mainPlaybackStopped))
        ]
        for (name, selector) in names {
            center.addObserver(self, selector: selector, name: name, object: nil)
        }

        center.addObserver(self,
                           selector: #selector(handleAudioSessionInterruption(_:)),
                           name: AVAudioSession.interruptionNotification,
                           object: nil)
        center.addObserver(self,
                           selector: #selector(handleAudioSessionRouteChange(_:)),
                           name: AVAudioSession.routeChangeNotification,
                           object: nil)
        center.addObserver(self,
                           selector: #selector(handleMediaServicesReset),
                           name: AVAudioSession.mediaServicesWereResetNotification,
                           object: nil)
    }

    @objc private func mainPlaybackStarted() {
        guard isEnabled else {
            return
        }
        if playback.numberOfVideoTracks > 0, !playback.playAsAudio {
            // The second channel must never play over a video (AGENTS 6.7).
            stop(reason: .followed)
            return
        }
        scheduleStart()
    }

    @objc private func mainPlaybackPaused() {
        pause()
    }

    @objc private func mainPlaybackStopped() {
        stop(reason: .followed)
    }

    /// Joins the main player a moment after it starts, so the two players do not
    /// race for the audio session during the first frames.
    private func scheduleStart() {
        pendingStart?.cancel()
        // The delayed play also rechecks the main player's state.
        guard isEnabled, playback.isPlaying, selectedURL != nil, !isPlaying else {
            return
        }
        let item = DispatchWorkItem { [weak self] in
            self?.play()
        }
        pendingStart = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.joinDelay, execute: item)
    }

    // MARK: - Audio session

    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else {
            return
        }
        switch type {
        case .began:
            pause()
        case .ended:
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            if options.contains(.shouldResume), playback.isPlaying {
                scheduleStart()
            }
        @unknown default:
            break
        }
    }

    @objc private func handleAudioSessionRouteChange(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else {
            return
        }
        pause()
    }

    /// The audio system restarted: leave both players silent, drop the mixer's
    /// player and let the follow logic rebuild it when the main one resumes.
    @objc private func handleMediaServicesReset() {
        playback.pause()
        pendingStart?.cancel()
        pendingStart = nil
        cancelFade()
        player?.delegate = nil
        player?.stop()
        player = nil
        loadedURL = nil
        needsReload = true
        isPlaying = false
        notifyChange()
    }

    // MARK: - Change notification

    private func notifyChange() {
        let center = notificationCenter
        if Thread.isMainThread {
            center.post(name: .discourseMixerDidChange, object: self)
        } else {
            DispatchQueue.main.async {
                center.post(name: .discourseMixerDidChange, object: self)
            }
        }
    }

    // MARK: - Display

    /// The mixer shows local files, whose library title is not part of the
    /// documented `audio_mixer_files` payload; the filename is used instead.
    static func displayTitle(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        let title = name.removingPercentEncoding ?? name
        return title.isEmpty ? url.lastPathComponent : title
    }
}

// MARK: - VLCMediaPlayerDelegate

extension DiscourseAudioMixer: VLCMediaPlayerDelegate {
    func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            switch newState {
            case .stopped:
                guard !self.isStopping, self.isPlaying else {
                    return
                }
                // VLCKit reports the end of a track as `.stopped`; a stop we
                // requested is flagged so it cannot restart the track.
                if self.isLooping, self.isEnabled {
                    self.restart(resetVolume: true)
                } else {
                    self.isPlaying = false
                    self.needsReload = true
                    self.notifyChange()
                }
            case .error:
                self.isPlaying = false
                self.needsReload = true
                self.notifyChange()
            default:
                break
            }
        }
    }
}
