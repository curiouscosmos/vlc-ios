/*****************************************************************************
 * DiscourseMixerTrackCell.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * One row of the Audio Mixer's track list: the local file's display title, a
 * checkmark on the selected track and a "Playing" note while it is the one the
 * mixer is playing. Reordering and deletion are owned by the table.
 *****************************************************************************/

import UIKit

final class DiscourseMixerTrackCell: UITableViewCell {
    static let reuseIdentifier = "DiscourseMixerTrackCell"

    private let containerView = UIView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let checkmarkView = UIImageView()

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

        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.layer.cornerRadius = 12
        containerView.layer.cornerCurve = .continuous
        containerView.layer.borderWidth = 1

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = DiscourseColors.current.secondaryText

        checkmarkView.translatesAutoresizingMaskIntoConstraints = false
        checkmarkView.image = UIImage(systemName: "checkmark.circle.fill")
        checkmarkView.contentMode = .scaleAspectFit
        checkmarkView.setContentHuggingPriority(.required, for: .horizontal)
        checkmarkView.widthAnchor.constraint(equalToConstant: 20).isActive = true

        let textStack = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 2

        contentView.addSubview(containerView)
        containerView.addSubview(textStack)
        containerView.addSubview(checkmarkView)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 3),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3),

            textStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 14),
            textStack.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 10),
            textStack.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -10),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: checkmarkView.leadingAnchor, constant: -10),

            checkmarkView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -14),
            checkmarkView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor)
        ])

        updateTheme()
    }

    // MARK: - Content

    func configure(title: String, isSelected: Bool, isPlaying: Bool) {
        titleLabel.text = title
        checkmarkView.isHidden = !isSelected
        let playingText = NSLocalizedString("MIXER_ROW_PLAYING",
                                            comment: "Shown on the Audio Mixer track that is playing")
        detailLabel.text = isPlaying ? playingText : nil
        detailLabel.isHidden = !isPlaying
        accessibilityIdentifier = "mixerTrack"
        accessibilityLabel = isPlaying ? [title, playingText].joined(separator: ", ") : title
        updateTheme()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        detailLabel.text = nil
        accessibilityLabel = nil
    }

    // MARK: - Theme

    func updateTheme() {
        let colors = DiscourseColors.current
        containerView.backgroundColor = colors.trackSurface
        containerView.layer.borderColor = colors.trackBorder.cgColor
        titleLabel.textColor = colors.trackText
        detailLabel.textColor = colors.accent
        checkmarkView.tintColor = colors.accent
    }
}
