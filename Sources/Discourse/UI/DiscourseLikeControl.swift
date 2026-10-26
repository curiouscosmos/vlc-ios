/*****************************************************************************
 * DiscourseLikeControl.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * The heart of the brief: a filled heart in the liked colour and a compact
 * count, an outlined heart in the unliked colour otherwise. The store owns the
 * optimistic state, so this view is a pure renderer of
 * `DiscourseLikeState`; the hosting screen performs the toggle and applies the
 * store change back to the visible control.
 *****************************************************************************/

import UIKit

/// What a like control should show for one discourse or track.
struct DiscourseLikeState {
    let isLiked: Bool
    let count: Int
    let isPending: Bool

    /// The store's optimistic count wins over the count that arrived with the
    /// list payload, so a refresh cannot undo a tap that is still in flight.
    static func resolve(target: DiscourseLikesStore.Target,
                        payloadLikes: Int,
                        store: DiscourseLikesStore = .shared) -> DiscourseLikeState {
        return DiscourseLikeState(isLiked: store.isLiked(target),
                                  count: store.count(for: target) ?? max(0, payloadLikes),
                                  isPending: store.isPending(target))
    }
}

final class DiscourseLikeControl: UIControl {
    /// Where the control is drawn: on a themed surface (cards, rows, headers) or
    /// on the audio player's dark navigation bar.
    enum Style {
        case surface
        case player
    }

    var style: Style = .surface {
        didSet { updateTheme() }
    }

    private let stackView = UIStackView()
    private let heartView = UIImageView()
    private let countLabel = UILabel()

    private var isLiked = false
    private var likeCount = 0
    private var title = ""
    private var isPending = false

    private static let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 15,
                                                                        weight: .semibold)

    init() {
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        return stackView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
    }

    /// The heart is small on purpose; keep the touch target at least 44 pt.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let dx = min(0, (bounds.width - 44) / 2)
        let dy = min(0, (bounds.height - 44) / 2)
        return bounds.insetBy(dx: dx, dy: dy).contains(point)
    }

    // MARK: - Setup

    private func setup() {
        isAccessibilityElement = true
        accessibilityTraits = .button

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 4
        stackView.isUserInteractionEnabled = false

        heartView.translatesAutoresizingMaskIntoConstraints = false
        heartView.contentMode = .scaleAspectFit
        heartView.setContentHuggingPriority(.required, for: .horizontal)
        heartView.setContentCompressionResistancePriority(.required, for: .horizontal)

        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = UIFont.monospacedDigitSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize,
                                                           weight: .medium)
        countLabel.adjustsFontForContentSizeCategory = true
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        stackView.addArrangedSubview(heartView)
        stackView.addArrangedSubview(countLabel)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            heartView.widthAnchor.constraint(equalToConstant: 18),
            heartView.heightAnchor.constraint(equalToConstant: 18)
        ])

        updateTheme()
    }

    // MARK: - Content

    func configure(isLiked: Bool, count: Int, title: String, isPending: Bool) {
        self.isLiked = isLiked
        likeCount = max(0, count)
        self.title = title
        self.isPending = isPending

        heartView.image = UIImage(systemName: isLiked ? "heart.fill" : "heart",
                                  withConfiguration: Self.symbolConfiguration)
        countLabel.text = DiscourseCountFormatter.string(for: likeCount)
        alpha = isPending ? 0.6 : 1

        updateAccessibility()
        updateTheme()
        invalidateIntrinsicContentSize()
    }

    func configure(with state: DiscourseLikeState, title: String) {
        configure(isLiked: state.isLiked,
                  count: state.count,
                  title: title,
                  isPending: state.isPending)
    }

    // MARK: - State

    override var isHighlighted: Bool {
        didSet {
            alpha = isHighlighted ? 0.5 : (isPending ? 0.6 : 1)
        }
    }

    // MARK: - Accessibility

    private func updateAccessibility() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let format = isLiked
            ? NSLocalizedString("DISCOURSE_UNLIKE_ACCESSIBILITY",
                                comment: "Accessibility label of a like button that removes the like: title, number of likes")
            : NSLocalizedString("DISCOURSE_LIKE_ACCESSIBILITY",
                                comment: "Accessibility label of a like button: title, number of likes")
        accessibilityLabel = String(format: format, trimmed, likeCount)
        accessibilityValue = isPending
            ? NSLocalizedString("DISCOURSE_LIKE_PENDING",
                                comment: "Accessibility value while a like request is in flight")
            : nil
    }

    // MARK: - Theme

    func updateTheme() {
        let colors = DiscourseColors.current
        switch style {
        case .surface:
            heartView.tintColor = isLiked ? colors.likedHeart : colors.unlikedHeart
            countLabel.textColor = colors.secondaryText
        case .player:
            heartView.tintColor = isLiked ? colors.likedHeart : .white
            countLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        }
    }
}
