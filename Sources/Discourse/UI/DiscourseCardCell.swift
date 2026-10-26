/*****************************************************************************
 * DiscourseCardCell.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * One catalogue card: square artwork, title (two lines), language, track count
 * and the like control, on a warm surface with a thin border. A small badge over
 * the artwork counts the discourse's downloads (the card keeps its height, which
 * the Home carousel depends on).
 *****************************************************************************/

import UIKit

final class DiscourseCardCell: UICollectionViewCell {
    static let reuseIdentifier = "DiscourseCardCell"

    private let cardView = UIView()
    private let artworkView = VLCNetworkImageView()
    private let titleLabel = UILabel()
    private let languageLabel = UILabel()
    private let metadataLabel = UILabel()
    private let likeControl = DiscourseLikeControl()
    private let accessibilityButton = DiscourseAccessibilityButton()

    private let downloadBadge = UIView()
    private let downloadIconView = UIImageView()
    private let downloadLabel = UILabel()

    private var artworkURL: URL?
    private var isDownloading = false

    /// Opens the discourse (VoiceOver activation; touches still select the cell).
    var onOpen: (() -> Void)?
    /// Toggles the discourse like from the heart.
    var onToggleLike: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setup() {
        isAccessibilityElement = false

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.layer.cornerRadius = 16
        cardView.layer.cornerCurve = .continuous
        cardView.layer.borderWidth = 1
        cardView.clipsToBounds = true

        artworkView.translatesAutoresizingMaskIntoConstraints = false
        artworkView.contentMode = .scaleAspectFill
        artworkView.clipsToBounds = true
        artworkView.layer.cornerRadius = 8
        artworkView.layer.cornerCurve = .continuous

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail

        languageLabel.translatesAutoresizingMaskIntoConstraints = false
        languageLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        languageLabel.adjustsFontForContentSizeCategory = true
        languageLabel.numberOfLines = 1

        metadataLabel.translatesAutoresizingMaskIntoConstraints = false
        metadataLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        metadataLabel.adjustsFontForContentSizeCategory = true
        metadataLabel.numberOfLines = 1
        metadataLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        likeControl.translatesAutoresizingMaskIntoConstraints = false
        likeControl.accessibilityIdentifier = "discourseCardLike"
        likeControl.addTarget(self, action: #selector(handleLike), for: .touchUpInside)

        accessibilityButton.translatesAutoresizingMaskIntoConstraints = false
        accessibilityButton.onActivate = { [weak self] in
            self?.onOpen?()
        }

        downloadBadge.translatesAutoresizingMaskIntoConstraints = false
        downloadBadge.layer.cornerRadius = 9
        downloadBadge.layer.cornerCurve = .continuous
        downloadBadge.layer.borderWidth = 1
        downloadBadge.isAccessibilityElement = true
        downloadBadge.accessibilityIdentifier = "discourseCardDownload"

        downloadIconView.translatesAutoresizingMaskIntoConstraints = false
        downloadIconView.contentMode = .scaleAspectFit
        downloadIconView.isAccessibilityElement = false

        downloadLabel.translatesAutoresizingMaskIntoConstraints = false
        downloadLabel.font = UIFont.monospacedDigitSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .caption2).pointSize,
                                                              weight: .semibold)
        downloadLabel.adjustsFontForContentSizeCategory = true

        let badgeContent = UIStackView(arrangedSubviews: [downloadIconView, downloadLabel])
        badgeContent.translatesAutoresizingMaskIntoConstraints = false
        badgeContent.axis = .horizontal
        badgeContent.alignment = .center
        badgeContent.spacing = 3
        badgeContent.isUserInteractionEnabled = false
        badgeContent.isAccessibilityElement = false
        downloadBadge.addSubview(badgeContent)

        let footer = UIStackView(arrangedSubviews: [metadataLabel, likeControl])
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.axis = .horizontal
        footer.alignment = .center
        footer.spacing = 8

        contentView.addSubview(cardView)
        cardView.addSubview(artworkView)
        cardView.addSubview(titleLabel)
        cardView.addSubview(languageLabel)
        cardView.addSubview(footer)
        cardView.addSubview(downloadBadge)
        cardView.addSubview(accessibilityButton)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            artworkView.topAnchor.constraint(equalTo: cardView.topAnchor),
            artworkView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            artworkView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            artworkView.heightAnchor.constraint(equalTo: artworkView.widthAnchor),

            titleLabel.topAnchor.constraint(equalTo: artworkView.bottomAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),

            languageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            languageLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            languageLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            footer.topAnchor.constraint(equalTo: languageLabel.bottomAnchor, constant: 4),
            footer.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12),

            downloadBadge.topAnchor.constraint(equalTo: artworkView.topAnchor, constant: 8),
            downloadBadge.trailingAnchor.constraint(equalTo: artworkView.trailingAnchor, constant: -8),
            downloadBadge.heightAnchor.constraint(equalToConstant: 18),

            badgeContent.leadingAnchor.constraint(equalTo: downloadBadge.leadingAnchor, constant: 6),
            badgeContent.trailingAnchor.constraint(equalTo: downloadBadge.trailingAnchor, constant: -6),
            badgeContent.centerYAnchor.constraint(equalTo: downloadBadge.centerYAnchor),
            downloadIconView.widthAnchor.constraint(equalToConstant: 11),
            downloadIconView.heightAnchor.constraint(equalToConstant: 11),

            accessibilityButton.topAnchor.constraint(equalTo: cardView.topAnchor),
            accessibilityButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            accessibilityButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            accessibilityButton.bottomAnchor.constraint(equalTo: cardView.bottomAnchor)
        ])

        updateTheme()
    }

    // MARK: - Content

    func configure(with discourse: Discourse,
                   like: DiscourseLikeState,
                   downloads: DiscourseDownloadSummary) {
        let title = discourse.title.trimmingCharacters(in: .whitespacesAndNewlines)
        titleLabel.text = title
        languageLabel.text = DiscourseMetadataText.language(discourse.language)

        let tracks = DiscourseMetadataText.tracks(discourse.totalTracks)
        let likes = DiscourseMetadataText.likes(like.count)
        metadataLabel.text = tracks
        likeControl.configure(with: like, title: title)

        let accessibilityText = [title, languageLabel.text, tracks, likes]
            .compactMap { $0 }
            .joined(separator: ", ")
        accessibilityButton.accessibilityLabel = accessibilityText
        // The cell is a container (the like control must stay focusable), but
        // its label still describes the card for UI tests and for the Home
        // screen's "open the card I just played" lookup.
        accessibilityLabel = accessibilityText

        configureDownloadBadge(downloads)

        let url = DiscourseURLResolver.resolve(discourse.thumbnailURLString)
        if url != artworkURL {
            artworkURL = url
            if let url {
                artworkView.setImageWith(url, maxPixelSize: 400)
            } else {
                artworkView.cancelLoading()
                artworkView.image = nil
            }
        }

        updateTheme()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        artworkView.cancelLoading()
        artworkURL = nil
        titleLabel.text = nil
        languageLabel.text = nil
        metadataLabel.text = nil
        accessibilityButton.accessibilityLabel = nil
        accessibilityLabel = nil
        downloadBadge.isHidden = true
        downloadBadge.accessibilityLabel = nil
        onOpen = nil
        onToggleLike = nil
    }

    // MARK: - Actions

    @objc private func handleLike() {
        onToggleLike?()
    }

    private func configureDownloadBadge(_ summary: DiscourseDownloadSummary) {
        downloadBadge.isHidden = !summary.isVisible
        guard summary.isVisible else {
            return
        }
        isDownloading = summary.isDownloading
        downloadLabel.text = summary.text
        downloadLabel.textColor = summary.isDownloading ? DiscourseColors.current.accent : DiscourseColors.current.downloaded
        downloadIconView.image = UIImage(systemName: summary.isDownloading ? "arrow.down.circle" : "arrow.down.circle.fill",
                                         withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
        downloadBadge.accessibilityLabel = summary.accessibilityLabel
        updateTheme()
    }

    // MARK: - Theme

    func updateTheme() {
        let colors = DiscourseColors.current
        cardView.backgroundColor = colors.surfaceStart
        cardView.layer.borderColor = colors.border.cgColor
        artworkView.backgroundColor = colors.trackSurface
        titleLabel.textColor = colors.primaryText
        languageLabel.textColor = colors.secondaryText
        metadataLabel.textColor = colors.trackSecondaryText
        downloadBadge.backgroundColor = colors.downloadedSurface
        downloadBadge.layer.borderColor = colors.downloadedBorder.cgColor
        downloadLabel.textColor = isDownloading ? colors.accent : colors.downloaded
        downloadIconView.tintColor = downloadLabel.textColor
        likeControl.updateTheme()
    }
}
