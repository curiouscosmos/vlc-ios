/*****************************************************************************
 * DiscourseRowView.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * The shared row for a discourse or a track: artwork, title, a metadata line
 * (discourse summary, or track discourse name + duration), the download control
 * (tracks only) and the like control.
 * Search results and the Home track lists host the same view in different cell
 * types, so both screens line up without a second row implementation.
 *****************************************************************************/

import UIKit

final class DiscourseRowView: UIView {
    private let containerView = UIView()
    private let artworkView = VLCNetworkImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let downloadControl = DiscourseDownloadControl()
    private let likeControl = DiscourseLikeControl()
    private let accessibilityButton = DiscourseAccessibilityButton()

    private var artworkURL: URL?
    private var isPlaying = false
    private var titleLeadingToArtwork: NSLayoutConstraint!
    private var titleLeadingToContainer: NSLayoutConstraint!
    private var titleTrailingToControls: NSLayoutConstraint!
    private var titleTrailingToContainer: NSLayoutConstraint!
    private var subtitleTrailingToControls: NSLayoutConstraint!
    private var subtitleTrailingToContainer: NSLayoutConstraint!

    /// Opens the discourse or starts the track (VoiceOver activation).
    var isPlaybackAvailable = true {
        didSet {
            if isPlaybackAvailable { accessibilityButton.accessibilityTraits.remove(.notEnabled) }
            else { accessibilityButton.accessibilityTraits.insert(.notEnabled) }
            if !isPlaybackAvailable {
                accessibilityButton.accessibilityValue = NSLocalizedString("Unavailable", comment: "Favourite media unavailable")
            } else {
                accessibilityButton.accessibilityValue = nil
            }
        }
    }

    var onOpen: (() -> Void)?
    /// Toggles the like from the heart.
    var onToggleLike: (() -> Void)?
    /// Downloads, cancels or retries the track from the arrow.
    var onToggleDownload: (() -> Void)?

    /// Text the hosting cell should expose as its accessibility label, built by
    /// the last `configure` call.
    private(set) var accessibilityText: String?
    private(set) var accessibilityValueText: String?

    init() {
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setup() {
        backgroundColor = .clear
        isAccessibilityElement = false

        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.layer.cornerRadius = 12
        containerView.layer.cornerCurve = .continuous
        containerView.layer.borderWidth = 1

        artworkView.translatesAutoresizingMaskIntoConstraints = false
        artworkView.contentMode = .scaleAspectFill
        artworkView.clipsToBounds = true
        artworkView.layer.cornerRadius = 8
        artworkView.layer.cornerCurve = .continuous
        artworkView.isAccessibilityElement = false

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.numberOfLines = 1
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        downloadControl.translatesAutoresizingMaskIntoConstraints = false
        downloadControl.addTarget(self, action: #selector(handleDownload), for: .touchUpInside)

        likeControl.translatesAutoresizingMaskIntoConstraints = false
        likeControl.addTarget(self, action: #selector(handleLike), for: .touchUpInside)

        accessibilityButton.translatesAutoresizingMaskIntoConstraints = false
        accessibilityButton.onActivate = { [weak self] in
            guard let self, self.isPlaybackAvailable else { return }
            self.onOpen?()
        }

        addSubview(containerView)
        containerView.addSubview(artworkView)
        containerView.addSubview(titleLabel)
        containerView.addSubview(subtitleLabel)
        containerView.addSubview(downloadControl)
        containerView.addSubview(likeControl)
        containerView.addSubview(accessibilityButton)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),

            artworkView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 10),
            artworkView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            artworkView.topAnchor.constraint(greaterThanOrEqualTo: containerView.topAnchor, constant: 8),
            artworkView.widthAnchor.constraint(equalToConstant: 52),
            artworkView.heightAnchor.constraint(equalTo: artworkView.widthAnchor),

            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 10),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -10),

            downloadControl.trailingAnchor.constraint(equalTo: likeControl.leadingAnchor, constant: -10),
            downloadControl.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),

            likeControl.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            likeControl.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),

            accessibilityButton.topAnchor.constraint(equalTo: containerView.topAnchor),
            accessibilityButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            accessibilityButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            accessibilityButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        // Local library rows may have no artwork, in which case the text starts
        // at the card's leading edge instead of after the empty artwork slot.
        titleLeadingToArtwork = titleLabel.leadingAnchor.constraint(equalTo: artworkView.trailingAnchor,
                                                                   constant: 12)
        titleLeadingToContainer = titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor,
                                                                      constant: 14)
        titleLeadingToArtwork.isActive = true

        // Local library rows have no like or download control, so their text
        // takes the full width; discourse rows stop before the controls.
        titleTrailingToControls = titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: downloadControl.leadingAnchor,
                                                                       constant: -8)
        titleTrailingToContainer = titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: containerView.trailingAnchor,
                                                                        constant: -12)
        subtitleTrailingToControls = subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: downloadControl.leadingAnchor,
                                                                             constant: -8)
        subtitleTrailingToContainer = subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: containerView.trailingAnchor,
                                                                              constant: -12)
        titleTrailingToControls.isActive = true
        subtitleTrailingToControls.isActive = true

        updateTheme()
    }

    // MARK: - Content

    func configure(with discourse: Discourse, like: DiscourseLikeState) {
        downloadControl.isHidden = true
        let title = discourse.title.trimmingCharacters(in: .whitespacesAndNewlines)
        titleLabel.text = title
        subtitleLabel.text = DiscourseMetadataText.summary(language: discourse.language,
                                                           tracks: discourse.totalTracks,
                                                           likes: like.count)
        isPlaying = false
        likeControl.configure(with: like, title: title)
        loadArtwork(discourse.thumbnailURL)
        buildAccessibility(title: title, subtitle: subtitleLabel.text)
        updateTheme()
    }

    /// A device-library track from Home's merged history: no like or download
    /// control, and the text may run to the card's trailing edge.
    func configure(with localTrack: DiscourseLocalTrack, isPlaying: Bool) {
        let title = localTrack.title.trimmingCharacters(in: .whitespacesAndNewlines)
        titleLabel.text = title
        subtitleLabel.text = localTrack.subtitle
        self.isPlaying = isPlaying
        setAccessoryControlsHidden(true)
        let hasArtwork = localTrack.artworkURL != nil
        artworkView.isHidden = !hasArtwork
        titleLeadingToArtwork.isActive = hasArtwork
        titleLeadingToContainer.isActive = !hasArtwork
        loadArtwork(localTrack.artworkURL)
        buildAccessibility(title: title, subtitle: localTrack.subtitle)
        updateTheme()
    }

    func configure(with track: DiscourseAudio,
                   isPlaying: Bool,
                   like: DiscourseLikeState,
                   download: DiscourseDownloadState) {
        let title = track.title.trimmingCharacters(in: .whitespacesAndNewlines)
        titleLabel.text = title

        // The duration moved into the metadata line; the trailing slot now holds
        // the like control.
        var subtitleParts: [String] = []
        let discourseName = track.discourseName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !discourseName.isEmpty {
            subtitleParts.append(discourseName)
        }
        if let duration = DiscourseDurationFormatter.string(forSeconds: track.durationSeconds) {
            subtitleParts.append(duration)
        }
        subtitleLabel.text = subtitleParts.joined(separator: " · ")

        self.isPlaying = isPlaying
        setAccessoryControlsHidden(false)
        artworkView.isHidden = false
        titleLeadingToArtwork.isActive = true
        titleLeadingToContainer.isActive = false
        likeControl.configure(with: like, title: title)
        downloadControl.configure(with: download, title: title)
        loadArtwork(track.thumbnailURL)
        buildAccessibility(title: title, subtitle: subtitleLabel.text)
        updateTheme()
    }

    func prepareForReuse() {
        artworkView.cancelLoading()
        artworkView.image = nil
        artworkURL = nil
        titleLabel.text = nil
        subtitleLabel.text = nil
        isPlaying = false
        isPlaybackAvailable = true
        onOpen = nil
        onToggleLike = nil
        onToggleDownload = nil
        setAccessoryControlsHidden(false)
        downloadControl.isHidden = true
        artworkView.isHidden = false
        titleLeadingToArtwork.isActive = true
        titleLeadingToContainer.isActive = false
        accessibilityText = nil
        accessibilityValueText = nil
    }

    private func setAccessoryControlsHidden(_ hidden: Bool) {
        downloadControl.isHidden = hidden
        likeControl.isHidden = hidden
        titleTrailingToControls.isActive = !hidden
        titleTrailingToContainer.isActive = hidden
        subtitleTrailingToControls.isActive = !hidden
        subtitleTrailingToContainer.isActive = hidden
    }

    // MARK: - Actions

    @objc private func handleLike() {
        onToggleLike?()
    }

    @objc private func handleDownload() {
        onToggleDownload?()
    }

    // MARK: - Artwork

    private func loadArtwork(_ url: URL?) {
        guard url != artworkURL else {
            return
        }
        artworkURL = url
        if let url {
            artworkView.setImageWith(url, maxPixelSize: 200)
        } else {
            artworkView.cancelLoading()
            artworkView.image = nil
        }
    }

    // MARK: - Accessibility

    private func buildAccessibility(title: String, subtitle: String?) {
        let parts = [title,
                     subtitle?.isEmpty == false ? subtitle : nil]
            .compactMap { $0 }
        accessibilityText = parts.joined(separator: ", ")
        accessibilityValueText = isPlaying ? NSLocalizedString("DISCOURSE_TRACK_PLAYING",
                                                              comment: "Accessibility value of the track being played") : nil
        accessibilityButton.accessibilityLabel = accessibilityText
        accessibilityButton.accessibilityValue = accessibilityValueText
    }

    // MARK: - Theme

    func updateTheme() {
        let colors = DiscourseColors.current
        containerView.backgroundColor = colors.trackSurface
        containerView.layer.borderColor = colors.trackBorder.cgColor
        artworkView.backgroundColor = colors.trackSurface
        titleLabel.textColor = isPlaying ? colors.accent : colors.trackText
        subtitleLabel.textColor = colors.trackSecondaryText
        downloadControl.updateTheme()
        likeControl.updateTheme()
    }
}
