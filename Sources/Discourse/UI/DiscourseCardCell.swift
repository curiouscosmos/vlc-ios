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
 * Shared discourse presentation for catalogue, Home, search and favourites.
 *****************************************************************************/

import UIKit

final class DiscourseCardCell: UICollectionViewCell {
    static let reuseIdentifier = "DiscourseCardCell"
    private let card = DiscourseCardView()

    var isPlaybackAvailable: Bool {
        get { card.isPlaybackAvailable }
        set { card.isPlaybackAvailable = newValue }
    }
    var onOpen: (() -> Void)? {
        get { card.onOpen }
        set { card.onOpen = newValue }
    }
    var onToggleLike: (() -> Void)? {
        get { card.onToggleLike }
        set { card.onToggleLike = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let width = layoutAttributes.size.width
        card.updateLayout(width: width)
        let size = contentView.systemLayoutSizeFitting(CGSize(width: width, height: 0),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        guard let attributes = layoutAttributes.copy() as? UICollectionViewLayoutAttributes else { return layoutAttributes }
        attributes.size = CGSize(width: width, height: ceil(size.height))
        return attributes
    }

    func configure(with discourse: Discourse, like: DiscourseLikeState, downloads: DiscourseDownloadSummary) {
        card.configure(with: discourse, like: like, downloads: downloads)
        accessibilityLabel = card.accessibilityLabel
    }
    func configureDownloadBadge(_ summary: DiscourseDownloadSummary) { card.configureDownloadBadge(summary) }
    func updateTheme() { card.updateTheme() }
    override func prepareForReuse() {
        super.prepareForReuse()
        card.prepareForReuse()
        accessibilityLabel = nil
    }
}

/// One view keeps table and collection cards identical, including their accessible actions.
final class DiscourseCardView: UIView {
    private let gradient = CAGradientLayer()
    private let artworkView = VLCNetworkImageView()
    private let titleLabel = UILabel()
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
    private let language = DiscourseCardMetadata(symbol: "globe", pill: true)
    private let location = DiscourseCardMetadata(symbol: "mappin.and.ellipse", pill: true)
    private let tracks = DiscourseCardMetadata(symbol: "square.3.layers.3d")
    private let date = DiscourseCardMetadata(symbol: "calendar")
    private let dateDivider = UIView()
    private let actionDivider = UIView()
    private let downloadIcon = UIImageView()
    private let downloadLabel = UILabel()
    private let downloadStatus = UIStackView()
    private let likeControl = DiscourseLikeControl()
    private let accessibilityButton = DiscourseAccessibilityButton()
    private let mainStack = UIStackView()
    private let pills = UIStackView()
    private let pillSpacer = UIView()
    private let footerSpacer = UIView()
    private let metadata = UIStackView()
    private let footer = UIStackView()
    private var artworkWidth: NSLayoutConstraint!
    private var accessibleTextWidth: NSLayoutConstraint!
    private var fullMetadataWidth: NSLayoutConstraint!
    private var artworkURL: URL?
    private var downloadSummary = DiscourseDownloadSummary(downloaded: 0, active: 0, total: 0)

    var onOpen: (() -> Void)?
    var onToggleLike: (() -> Void)?
    var isPlaybackAvailable = true {
        didSet {
            if isPlaybackAvailable { accessibilityButton.accessibilityTraits.remove(.notEnabled) }
            else { accessibilityButton.accessibilityTraits.insert(.notEnabled) }
            accessibilityButton.accessibilityValue = isPlaybackAvailable ? nil
                : NSLocalizedString("Unavailable", comment: "Favourite media unavailable")
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        isAccessibilityElement = false
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        clipsToBounds = true
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        layer.insertSublayer(gradient, at: 0)

        artworkView.contentMode = .scaleAspectFill
        artworkView.clipsToBounds = true
        artworkView.layer.cornerRadius = 10
        artworkView.layer.cornerCurve = .continuous
        artworkView.isAccessibilityElement = false
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 2
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        chevron.contentMode = .scaleAspectFit
        chevron.isAccessibilityElement = false
        let heading = UIStackView(arrangedSubviews: [titleLabel, chevron])
        heading.alignment = .top
        heading.spacing = 12
        chevron.widthAnchor.constraint(equalToConstant: 10).isActive = true
        chevron.heightAnchor.constraint(equalToConstant: 20).isActive = true

        pills.spacing = 6
        pills.alignment = .leading
        pills.addArrangedSubview(language)
        pills.addArrangedSubview(location)
        pills.addArrangedSubview(pillSpacer)
        pillSpacer.setContentHuggingPriority(UILayoutPriority(1), for: .horizontal)
        for item in [language, location] { item.setContentHuggingPriority(.required, for: .horizontal) }
        language.setContentCompressionResistancePriority(.required, for: .horizontal)
        location.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        metadata.spacing = 8
        metadata.alignment = .leading
        metadata.addArrangedSubview(tracks)
        metadata.addArrangedSubview(dateDivider)
        metadata.addArrangedSubview(date)
        date.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        downloadIcon.contentMode = .scaleAspectFit
        downloadLabel.font = .preferredFont(forTextStyle: .caption2)
        downloadLabel.adjustsFontForContentSizeCategory = true
        downloadStatus.alignment = .center
        downloadStatus.spacing = 3
        downloadStatus.addArrangedSubview(downloadIcon)
        downloadStatus.addArrangedSubview(downloadLabel)
        downloadStatus.isAccessibilityElement = true
        downloadStatus.accessibilityIdentifier = "discourseCardDownload"
        likeControl.style = .card
        likeControl.accessibilityIdentifier = "discourseCardLike"
        likeControl.addTarget(self, action: #selector(handleLike), for: .touchUpInside)
        let actions = UIStackView(arrangedSubviews: [downloadStatus, actionDivider, likeControl])
        actions.spacing = 10
        actions.alignment = .center
        actions.setContentCompressionResistancePriority(.required, for: .horizontal)
        actions.setContentHuggingPriority(.required, for: .horizontal)
        footer.spacing = 10
        footer.alignment = .center
        metadata.setContentHuggingPriority(.required, for: .horizontal)
        footerSpacer.setContentHuggingPriority(UILayoutPriority(1), for: .horizontal)
        footer.addArrangedSubview(metadata)
        footer.addArrangedSubview(footerSpacer)
        footer.addArrangedSubview(actions)
        fullMetadataWidth = metadata.widthAnchor.constraint(equalTo: footer.widthAnchor)
        let text = UIStackView(arrangedSubviews: [heading, pills, footer])
        text.axis = .vertical
        text.distribution = .equalSpacing
        text.spacing = 10
        mainStack.alignment = .top
        mainStack.spacing = 12
        mainStack.addArrangedSubview(artworkView)
        mainStack.addArrangedSubview(text)
        accessibleTextWidth = text.widthAnchor.constraint(equalTo: mainStack.widthAnchor)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mainStack)

        accessibilityButton.translatesAutoresizingMaskIntoConstraints = false
        accessibilityButton.onActivate = { [weak self] in
            guard let self, self.isPlaybackAvailable else { return }
            self.onOpen?()
        }
        addSubview(accessibilityButton)
        accessibilityElements = [accessibilityButton, downloadStatus, likeControl]
        artworkWidth = artworkView.widthAnchor.constraint(equalToConstant: 88)
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            artworkWidth, artworkView.heightAnchor.constraint(equalTo: artworkView.widthAnchor),
            text.heightAnchor.constraint(greaterThanOrEqualTo: artworkView.heightAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 132),
            downloadIcon.widthAnchor.constraint(equalToConstant: 22),
            downloadIcon.heightAnchor.constraint(equalToConstant: 22),
            dateDivider.widthAnchor.constraint(equalToConstant: 1),
            dateDivider.heightAnchor.constraint(equalToConstant: 16),
            actionDivider.widthAnchor.constraint(equalToConstant: 1),
            actionDivider.heightAnchor.constraint(equalToConstant: 20),
            accessibilityButton.topAnchor.constraint(equalTo: topAnchor),
            accessibilityButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            accessibilityButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            accessibilityButton.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        updateLayout()
        updateTheme()
    }

    override func layoutSubviews() {
        updateLayout()
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
    }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateLayout()
    }
    fileprivate func updateLayout(width: CGFloat? = nil) {
        let width = width ?? bounds.width
        let accessible = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        accessibleTextWidth?.isActive = accessible
        mainStack.axis = accessible ? .vertical : .horizontal
        mainStack.alignment = accessible ? .leading : .top
        artworkWidth.constant = max(72, min(160, width * 0.2))
        pills.axis = accessible ? .vertical : .horizontal
        pillSpacer.isHidden = accessible
        metadata.axis = width >= 650 && !accessible ? .horizontal : .vertical
        metadata.alignment = metadata.axis == .horizontal ? .center : .leading
        dateDivider.isHidden = date.isHidden || metadata.axis == .vertical
        footer.axis = width < 330 || accessible ? .vertical : .horizontal
        footer.alignment = footer.axis == .vertical ? .trailing : .center
        footerSpacer.isHidden = footer.axis == .vertical
        fullMetadataWidth?.isActive = footer.axis == .vertical
    }

    func configure(with discourse: Discourse, like: DiscourseLikeState, downloads: DiscourseDownloadSummary) {
        let title = discourse.title.trimmingCharacters(in: .whitespacesAndNewlines)
        titleLabel.text = title
        let languageText = DiscourseMetadataText.language(discourse.language)
        let locationText = DiscourseMetadataText.location(discourse.location)
        let dateText = DiscourseMetadataText.date(discourse.date)
        language.setText(languageText.isEmpty ? nil : languageText)
        location.setText(locationText)
        pills.isHidden = language.isHidden && location.isHidden
        tracks.setText(DiscourseMetadataText.tracks(discourse.totalTracks))
        date.setText(dateText)
        likeControl.configure(with: like, title: title)
        let label = [title, languageText.isEmpty ? nil : languageText, locationText, tracks.text, dateText,
                     DiscourseMetadataText.likes(like.count)].compactMap { $0 }.joined(separator: ", ")
        accessibilityButton.accessibilityLabel = label
        accessibilityLabel = label
        configureDownloadBadge(downloads)
        let url = discourse.thumbnailURL
        if url != artworkURL {
            artworkURL = url
            if let url { artworkView.setImageWith(url, maxPixelSize: 400) }
            else { artworkView.cancelLoading(); artworkView.image = nil }
        }
        updateLayout()
        updateTheme()
    }

    func configureDownloadBadge(_ summary: DiscourseDownloadSummary) {
        downloadSummary = summary
        downloadLabel.text = summary.text
        downloadLabel.isHidden = !summary.isVisible
        downloadIcon.image = UIImage(systemName: summary.isDownloading ? "arrow.down.circle"
            : summary.total > 0 && summary.downloaded >= summary.total ? "arrow.down.circle.fill" : "square.and.arrow.down",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .regular))
        downloadStatus.accessibilityLabel = summary.isVisible ? summary.accessibilityLabel
            : NSLocalizedString("DISCOURSE_CARD_NO_DOWNLOADS", comment: "Discourse download status")
        updateTheme()
    }
    func prepareForReuse() {
        artworkView.cancelLoading()
        artworkView.image = nil
        artworkURL = nil
        titleLabel.text = nil
        language.setText(nil); location.setText(nil); date.setText(nil); tracks.setText(nil)
        accessibilityButton.accessibilityLabel = nil
        accessibilityLabel = nil
        isPlaybackAvailable = true
        onOpen = nil; onToggleLike = nil
    }
    @objc private func handleLike() { onToggleLike?() }

    func updateTheme() {
        let colors = DiscourseColors.current
        gradient.colors = [colors.surfaceStart.cgColor, colors.surfaceEnd.cgColor]
        layer.borderColor = colors.border.cgColor
        artworkView.backgroundColor = colors.trackSurface
        titleLabel.textColor = colors.primaryText
        chevron.tintColor = colors.primaryText
        for item in [language, location, tracks, date] { item.updateTheme() }
        dateDivider.backgroundColor = colors.secondaryText.withAlphaComponent(0.5)
        actionDivider.backgroundColor = colors.secondaryText.withAlphaComponent(0.5)
        let tint = downloadSummary.isDownloading ? colors.accent
            : downloadSummary.downloaded > 0 ? colors.downloaded : colors.primaryText
        downloadIcon.tintColor = tint
        downloadLabel.textColor = tint
        likeControl.updateTheme()
    }
}

private final class DiscourseCardMetadata: UIView {
    private let label = UILabel()
    private let icon: UIImageView
    private let pill: Bool
    var text: String? { label.text }

    init(symbol: String, pill: Bool = false) {
        icon = UIImageView(image: UIImage(systemName: symbol))
        self.pill = pill
        super.init(frame: .zero)
        label.font = .preferredFont(forTextStyle: .caption1)
        label.adjustsFontForContentSizeCategory = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        icon.contentMode = .scaleAspectFit
        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.spacing = 5
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        let padding: CGFloat = pill ? 8 : 0
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: pill ? 5 : 0),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: pill ? -5 : 0),
            icon.widthAnchor.constraint(equalToConstant: 16), icon.heightAnchor.constraint(equalToConstant: 16)
        ])
        setContentCompressionResistancePriority(.required, for: .vertical)
        layer.borderWidth = pill ? 1 : 0
        layer.cornerCurve = .continuous
        isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize {
        let padding: CGFloat = pill ? 16 : 0
        return CGSize(width: label.intrinsicContentSize.width + 21 + padding,
                      height: max(16, label.intrinsicContentSize.height) + (pill ? 10 : 0))
    }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        invalidateIntrinsicContentSize()
    }
    override func layoutSubviews() { super.layoutSubviews(); layer.cornerRadius = pill ? bounds.height / 2 : 0 }
    func setText(_ text: String?) {
        label.text = text
        isHidden = text == nil
        invalidateIntrinsicContentSize()
    }
    func updateTheme() {
        let colors = DiscourseColors.current
        label.textColor = colors.secondaryText
        icon.tintColor = colors.secondaryText
        backgroundColor = pill ? colors.primaryText.withAlphaComponent(0.08) : .clear
        layer.borderColor = colors.primaryText.withAlphaComponent(0.1).cgColor
    }
}
