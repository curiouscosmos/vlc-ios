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
 * summary, optional city/date chips and the "Play all" action.
 *****************************************************************************/

import UIKit

final class DiscourseDetailHeaderView: UIView {
    private let artworkView = VLCNetworkImageView()
    private let titleLabel = UILabel()
    private let metadataLabel = UILabel()
    private let locationChip = DiscourseCardMetadata(symbol: "mappin.and.ellipse", pill: true)
    private let dateChip = DiscourseCardMetadata(symbol: "calendar", pill: true)
    private let chips = UIStackView()
    private let actionsStack = UIStackView()
    private let textStack = UIStackView()
    private let stack = UIStackView()
    private var accessibleTextWidth: NSLayoutConstraint?
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
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        configuration.titleLineBreakMode = .byClipping
        playAllButton.configuration = configuration
        playAllButton.translatesAutoresizingMaskIntoConstraints = false
        playAllButton.accessibilityIdentifier = "discoursePlayAll"

        likeControl.translatesAutoresizingMaskIntoConstraints = false
        likeControl.accessibilityIdentifier = "discourseDetailLike"

        actionsStack.addArrangedSubview(chips)
        actionsStack.addArrangedSubview(UIView())
        actionsStack.addArrangedSubview(playAllButton)
        playAllButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        actionsStack.axis = .horizontal
        actionsStack.alignment = .center
        actionsStack.spacing = 8

        chips.axis = .horizontal
        chips.alignment = .center
        chips.spacing = 6
        chips.addArrangedSubview(locationChip)
        chips.addArrangedSubview(dateChip)
        for chip in [locationChip, dateChip] {
            chip.isAccessibilityElement = true
            chip.accessibilityTraits = .staticText
        }
        locationChip.accessibilityIdentifier = "discourseDetailLocation"
        dateChip.accessibilityIdentifier = "discourseDetailDate"

        for view in [titleLabel, metadataLabel, likeControl] { textStack.addArrangedSubview(view) }
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 8

        stack.addArrangedSubview(artworkView)
        stack.addArrangedSubview(textStack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .top
        stack.spacing = 16
        let contentStack = UIStackView(arrangedSubviews: [stack, actionsStack])
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 16
        addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),

            artworkView.widthAnchor.constraint(equalToConstant: 128),
            artworkView.heightAnchor.constraint(equalTo: artworkView.widthAnchor)
        ])

        accessibleTextWidth = textStack.widthAnchor.constraint(equalTo: stack.widthAnchor)
        updateLayout()
        updateTheme()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateLayout()
    }

    private func updateLayout() {
        let accessible = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        stack.axis = accessible ? .vertical : .horizontal
        stack.alignment = accessible ? .leading : .top
        accessibleTextWidth?.isActive = accessible
        actionsStack.axis = accessible ? .vertical : .horizontal
        actionsStack.alignment = accessible ? .leading : .center
        chips.axis = accessible ? .vertical : .horizontal
        chips.alignment = accessible ? .leading : .center
    }

    // MARK: - Content

    func configure(with discourse: Discourse, like: DiscourseLikeState) {
        let title = discourse.title.trimmingCharacters(in: .whitespacesAndNewlines)
        titleLabel.text = title
        locationChip.setText(DiscourseMetadataText.location(discourse.location))
        dateChip.setText(DiscourseMetadataText.date(discourse.date))
        locationChip.accessibilityLabel = locationChip.text
        dateChip.accessibilityLabel = dateChip.text
        chips.isHidden = locationChip.isHidden && dateChip.isHidden
        metadataLabel.text = DiscourseMetadataText.summary(language: discourse.language,
                                                           tracks: discourse.totalTracks,
                                                           likes: 0)
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
        locationChip.updateTheme()
        dateChip.updateTheme()
    }
}
