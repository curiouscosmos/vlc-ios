/*****************************************************************************
 * DiscourseDetailHeaderView.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * The table header of a discourse: artwork, title, the language/track/like
 * summary and the "Play all" action.
 *****************************************************************************/

import UIKit

final class DiscourseDetailHeaderView: UIView {
    private let artworkView = VLCNetworkImageView()
    private let titleLabel = UILabel()
    private let metadataLabel = UILabel()
    let playAllButton = UIButton(type: .system)
    let likeControl = DiscourseLikeControl()

    private var artworkURL: URL?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setup() {
        backgroundColor = .clear

        artworkView.translatesAutoresizingMaskIntoConstraints = false
        artworkView.contentMode = .scaleAspectFill
        artworkView.clipsToBounds = true
        artworkView.layer.cornerRadius = 8
        artworkView.layer.cornerCurve = .continuous
        artworkView.isAccessibilityElement = false
        artworkView.setContentHuggingPriority(.required, for: .horizontal)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.preferredFont(forTextStyle: .title2)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 3
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.accessibilityTraits = .header

        metadataLabel.translatesAutoresizingMaskIntoConstraints = false
        metadataLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        metadataLabel.adjustsFontForContentSizeCategory = true
        metadataLabel.numberOfLines = 2
        metadataLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        var configuration = UIButton.Configuration.filled()
        configuration.title = NSLocalizedString("DISCOURSE_DETAIL_PLAY_ALL",
                                                comment: "Play all tracks of a discourse")
        configuration.image = UIImage(systemName: "play.fill")
        configuration.imagePadding = 8
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20)
        playAllButton.configuration = configuration
        playAllButton.translatesAutoresizingMaskIntoConstraints = false
        playAllButton.accessibilityIdentifier = "discoursePlayAll"

        likeControl.translatesAutoresizingMaskIntoConstraints = false
        likeControl.accessibilityIdentifier = "discourseDetailLike"

        let actionsStack = UIStackView(arrangedSubviews: [playAllButton, likeControl])
        actionsStack.axis = .horizontal
        actionsStack.alignment = .center
        actionsStack.spacing = 12

        let textStack = UIStackView(arrangedSubviews: [titleLabel, metadataLabel, actionsStack])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 8

        let stack = UIStackView(arrangedSubviews: [artworkView, textStack])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .top
        stack.spacing = 16
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),

            artworkView.widthAnchor.constraint(equalToConstant: 128),
            artworkView.heightAnchor.constraint(equalTo: artworkView.widthAnchor)
        ])

        updateTheme()
    }

    // MARK: - Content

    func configure(with discourse: Discourse, like: DiscourseLikeState) {
        let title = discourse.title.trimmingCharacters(in: .whitespacesAndNewlines)
        titleLabel.text = title
        metadataLabel.text = DiscourseMetadataText.summary(language: discourse.language,
                                                           tracks: discourse.totalTracks,
                                                           likes: like.count)
        likeControl.configure(with: like, title: title)

        let url = DiscourseURLResolver.resolve(discourse.thumbnailURLString)
        if url != artworkURL {
            artworkURL = url
            if let url {
                artworkView.setImageWith(url, maxPixelSize: 512)
            } else {
                artworkView.cancelLoading()
                artworkView.image = nil
            }
        }
        updateTheme()
    }

    func setPlayAllEnabled(_ enabled: Bool) {
        playAllButton.isEnabled = enabled
    }

    // MARK: - Theme

    func updateTheme() {
        let colors = DiscourseColors.current
        titleLabel.textColor = colors.primaryText
        metadataLabel.textColor = colors.secondaryText
        artworkView.backgroundColor = colors.trackSurface
        playAllButton.configuration?.baseBackgroundColor = colors.accent
        playAllButton.configuration?.baseForegroundColor = .white
        likeControl.updateTheme()
    }
}
