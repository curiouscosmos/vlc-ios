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
 * One discourse card, on a warm surface with a thin border. `Layout.tile` (the
 * Home carousel) stacks square artwork above the title, language, track count
 * and the like control, with the download badge over the artwork. `Layout.list`
 * (the catalogue) is a full-width row: artwork on the left, the same content on
 * the right and the download badge folded into the footer. Both layouts share
 * the like control, the badge state and the VoiceOver "open" overlay.
 *****************************************************************************/

import UIKit

private final class TopAlignedLabel: UILabel {
    override func drawText(in rect: CGRect) {
        var textRect = rect
        textRect.size.height = sizeThatFits(CGSize(width: rect.width, height: .greatestFiniteMagnitude)).height
        super.drawText(in: textRect)
    }
}

final class DiscourseCardCell: UICollectionViewCell {
    static let reuseIdentifier = "DiscourseCardCell"

    /// How the card arranges its content. A cell keeps one layout for the
    /// collection view that dequeued it (Home = tile, catalogue = list), so
    /// switching layouts never reloads the other screen.
    enum Layout {
        case tile
        case list
    }

    var layoutStyle: Layout = .tile {
        didSet {
            guard layoutStyle != oldValue else { return }
            apply(layoutStyle)
        }
    }

    private let cardView = UIView()
    private let artworkView = VLCNetworkImageView()
    private let titleLabel = TopAlignedLabel()
    private let languageLabel = UILabel()
    private let metadataLabel = UILabel()
    private let contentStack = UIStackView()
    private let footer = UIStackView()
    private let likeControl = DiscourseLikeControl()
    private let accessibilityButton = DiscourseAccessibilityButton()

    private let downloadBadge = UIView()
    private let downloadIconView = UIImageView()
    private let downloadLabel = UILabel()

    private var artworkURL: URL?
    private var isDownloading = false
    private var tileConstraints: [NSLayoutConstraint] = []
    private var listConstraints: [NSLayoutConstraint] = []
    private var titleHeightConstraint: NSLayoutConstraint!

    /// Opens the discourse (VoiceOver activation; touches still select the cell).
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
        titleHeightConstraint = titleLabel.heightAnchor.constraint(equalToConstant: ceil(titleLabel.font.lineHeight * 2))
        titleHeightConstraint.isActive = true

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
            guard let self, self.isPlaybackAvailable else { return }
            self.onOpen?()
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

        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.axis = .horizontal
        footer.alignment = .center
        footer.spacing = 8
        metadataLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        likeControl.setContentHuggingPriority(.required, for: .horizontal)
        likeControl.setContentCompressionResistancePriority(.required, for: .horizontal)
        footer.addArrangedSubview(metadataLabel)
        footer.addArrangedSubview(likeControl)

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 2
        contentStack.addArrangedSubview(titleLabel)
        contentStack.addArrangedSubview(languageLabel)
        contentStack.addArrangedSubview(footer)
        contentStack.setCustomSpacing(4, after: languageLabel)

        contentView.addSubview(cardView)
        cardView.addSubview(artworkView)
        cardView.addSubview(contentStack)
        cardView.addSubview(downloadBadge)
        cardView.addSubview(accessibilityButton)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

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

        // Square artwork above the text, badge over the artwork's corner.
        tileConstraints = [
            artworkView.topAnchor.constraint(equalTo: cardView.topAnchor),
            artworkView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            artworkView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            artworkView.heightAnchor.constraint(equalTo: artworkView.widthAnchor),

            contentStack.topAnchor.constraint(equalTo: artworkView.bottomAnchor, constant: 10),
            contentStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            contentStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            contentStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12),

            downloadBadge.topAnchor.constraint(equalTo: artworkView.topAnchor, constant: 8),
            downloadBadge.trailingAnchor.constraint(equalTo: artworkView.trailingAnchor, constant: -8)
        ]

        // Full-width row: artwork on the left, the text block on the right.
        // The content block is centred and the card keeps a 112 pt minimum, so
        // a one-line title still leaves a comfortably tall row around the 88 pt
        // artwork.
        listConstraints = [
            artworkView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            artworkView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            artworkView.widthAnchor.constraint(equalToConstant: 88),
            artworkView.heightAnchor.constraint(equalToConstant: 88),
            artworkView.topAnchor.constraint(greaterThanOrEqualTo: cardView.topAnchor, constant: 12),
            artworkView.bottomAnchor.constraint(lessThanOrEqualTo: cardView.bottomAnchor, constant: -12),

            contentStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            contentStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12),
            contentStack.leadingAnchor.constraint(equalTo: artworkView.trailingAnchor, constant: 12),
            contentStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),

            cardView.heightAnchor.constraint(greaterThanOrEqualToConstant: 112)
        ]

        NSLayoutConstraint.activate(tileConstraints)

        updateTheme()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        titleHeightConstraint?.constant = ceil(UIFont.preferredFont(forTextStyle: .headline,
                                                                   compatibleWith: traitCollection).lineHeight * 2)
    }

    /// Swaps the constraint set and moves the download badge from the artwork
    /// corner (tile) into the footer (list), where it cannot cover the smaller
    /// list thumbnail.
    private func apply(_ layout: Layout) {
        NSLayoutConstraint.deactivate(layout == .tile ? listConstraints : tileConstraints)

        switch layout {
        case .tile:
            downloadBadge.removeFromSuperview()
            cardView.addSubview(downloadBadge)
            NSLayoutConstraint.activate(tileConstraints)
        case .list:
            downloadBadge.removeFromSuperview()
            footer.insertArrangedSubview(downloadBadge, at: footer.arrangedSubviews.count - 1)
            NSLayoutConstraint.activate(listConstraints)
        }
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
        isPlaybackAvailable = true
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
