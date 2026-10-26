/*****************************************************************************
 * DiscourseTrackCell.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * One row of a discourse: the position inside a progress ring (or the playing
 * speaker, or a checkmark once finished), the title, the duration, the download
 * control and the like control.
 *****************************************************************************/

import UIKit

final class DiscourseTrackCell: UITableViewCell {
    static let reuseIdentifier = "DiscourseTrackCell"

    private let containerView = UIView()
    private let progressView = DiscourseTrackProgressView()
    private let titleLabel = UILabel()
    private let durationLabel = UILabel()
    private let downloadControl = DiscourseDownloadControl()
    private let likeControl = DiscourseLikeControl()
    private let accessibilityButton = DiscourseAccessibilityButton()

    /// Opens the track (VoiceOver activation; the table's selection handles taps).
    var onOpen: (() -> Void)?
    /// Toggles the track like from the heart.
    var onToggleLike: (() -> Void)?
    /// Downloads, cancels or retries the track from the arrow.
    var onToggleDownload: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setup() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none
        isAccessibilityElement = false

        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.layer.cornerRadius = 12
        containerView.layer.cornerCurve = .continuous
        containerView.layer.borderWidth = 1

        progressView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail

        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        durationLabel.adjustsFontForContentSizeCategory = true
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)
        durationLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        downloadControl.translatesAutoresizingMaskIntoConstraints = false
        downloadControl.accessibilityIdentifier = "discourseTrackDownload"
        downloadControl.addTarget(self, action: #selector(handleDownload), for: .touchUpInside)

        likeControl.translatesAutoresizingMaskIntoConstraints = false
        likeControl.accessibilityIdentifier = "discourseTrackLike"
        likeControl.addTarget(self, action: #selector(handleLike), for: .touchUpInside)

        accessibilityButton.translatesAutoresizingMaskIntoConstraints = false
        accessibilityButton.onActivate = { [weak self] in
            self?.onOpen?()
        }

        let trailingStack = UIStackView(arrangedSubviews: [durationLabel,
                                                           downloadControl,
                                                           likeControl])
        trailingStack.translatesAutoresizingMaskIntoConstraints = false
        trailingStack.axis = .horizontal
        trailingStack.alignment = .center
        trailingStack.spacing = 10

        contentView.addSubview(containerView)
        containerView.addSubview(progressView)
        containerView.addSubview(titleLabel)
        containerView.addSubview(trailingStack)
        containerView.addSubview(accessibilityButton)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 3),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3),

            progressView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 10),
            progressView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            progressView.topAnchor.constraint(greaterThanOrEqualTo: containerView.topAnchor, constant: 8),

            titleLabel.leadingAnchor.constraint(equalTo: progressView.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 10),
            titleLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingStack.leadingAnchor, constant: -10),

            trailingStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            trailingStack.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            trailingStack.topAnchor.constraint(greaterThanOrEqualTo: containerView.topAnchor, constant: 6),

            accessibilityButton.topAnchor.constraint(equalTo: containerView.topAnchor),
            accessibilityButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            accessibilityButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            accessibilityButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        updateTheme()
    }

    // MARK: - Content

    func configure(with track: DiscourseAudio,
                   position: Int,
                   fraction: Double,
                   isCompleted: Bool,
                   isPlaying: Bool,
                   like: DiscourseLikeState,
                   download: DiscourseDownloadState) {
        let title = track.title.trimmingCharacters(in: .whitespacesAndNewlines)
        titleLabel.text = title.isEmpty ? String(format: NSLocalizedString("DISCOURSE_TRACK_FALLBACK_TITLE",
                                                                          comment: "Title shown when a track has no title"),
                                                 position) : title

        if let duration = DiscourseDurationFormatter.string(forSeconds: track.durationSeconds) {
            durationLabel.text = duration
            durationLabel.isHidden = false
        } else {
            durationLabel.text = nil
            durationLabel.isHidden = true
        }

        progressView.configure(position: position,
                               fraction: fraction,
                               isCompleted: isCompleted,
                               isPlaying: isPlaying)
        likeControl.configure(with: like, title: titleLabel.text ?? title)
        downloadControl.configure(with: download, title: titleLabel.text ?? title)

        accessibilityButton.accessibilityLabel = [titleLabel.text, durationLabel.text]
            .compactMap { $0 }
            .joined(separator: ", ")
        if isPlaying {
            accessibilityButton.accessibilityValue = NSLocalizedString("DISCOURSE_TRACK_PLAYING",
                                                                      comment: "Accessibility value of the track being played")
        } else if isCompleted {
            accessibilityButton.accessibilityValue = NSLocalizedString("DISCOURSE_TRACK_PLAYED",
                                                                      comment: "Accessibility value of a finished track")
        } else {
            accessibilityButton.accessibilityValue = nil
        }

        updateTheme()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        durationLabel.text = nil
        progressView.configure(position: 0, fraction: 0, isCompleted: false, isPlaying: false)
        accessibilityButton.accessibilityLabel = nil
        accessibilityButton.accessibilityValue = nil
        onOpen = nil
        onToggleLike = nil
        onToggleDownload = nil
    }

    // MARK: - Actions

    @objc private func handleLike() {
        onToggleLike?()
    }

    @objc private func handleDownload() {
        onToggleDownload?()
    }

    // MARK: - Theme

    func updateTheme() {
        let colors = DiscourseColors.current
        containerView.backgroundColor = colors.trackSurface
        containerView.layer.borderColor = colors.trackBorder.cgColor
        titleLabel.textColor = colors.trackText
        durationLabel.textColor = colors.trackSecondaryText
        progressView.updateTheme()
        downloadControl.updateTheme()
        likeControl.updateTheme()
    }
}
