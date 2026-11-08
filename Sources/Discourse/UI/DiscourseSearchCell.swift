/*****************************************************************************
 * DiscourseSearchCell.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * A search result row. The content lives in DiscourseRowView, shared with the
 * Home screen's track lists; the cell only adds the list padding, the
 * accessibility element and the test identifiers.
 *****************************************************************************/

import UIKit

final class DiscourseSearchCell: UITableViewCell {
    static let reuseIdentifier = "DiscourseSearchCell"

    private let rowView = DiscourseRowView()
    private let discourseCard = DiscourseCardView()
    private let stack = UIStackView()

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

        discourseCard.isHidden = true
        stack.addArrangedSubview(rowView)
        stack.addArrangedSubview(discourseCard)
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = .zero
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    // MARK: - Content

    var onOpen: (() -> Void)? {
        get { rowView.onOpen }
        set { rowView.onOpen = newValue; discourseCard.onOpen = newValue }
    }

    var onToggleLike: (() -> Void)? {
        get { rowView.onToggleLike }
        set { rowView.onToggleLike = newValue; discourseCard.onToggleLike = newValue }
    }

    var onToggleDownload: (() -> Void)? {
        get { rowView.onToggleDownload }
        set { rowView.onToggleDownload = newValue }
    }

    func configure(with discourse: Discourse, like: DiscourseLikeState) {
        rowView.isHidden = true
        discourseCard.isHidden = false
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0)
        discourseCard.configure(with: discourse, like: like,
                               downloads: .resolve(discourseID: discourse.id, totalTracks: discourse.totalTracks))
        accessibilityIdentifier = "discourseSearchDiscourse"
    }

    func configureDownloadBadge(_ summary: DiscourseDownloadSummary) { discourseCard.configureDownloadBadge(summary) }

    func updateDownload(_ state: DiscourseDownloadState) {
        rowView.updateDownload(state)
    }

    func configure(with track: DiscourseAudio,
                   isPlaying: Bool,
                   like: DiscourseLikeState,
                   download: DiscourseDownloadState) {
        rowView.isHidden = false
        discourseCard.isHidden = true
        stack.directionalLayoutMargins = .zero
        rowView.configure(with: track,
                          isPlaying: isPlaying,
                          like: like,
                          download: download)
        accessibilityIdentifier = "discourseSearchTrack"
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        rowView.prepareForReuse()
        discourseCard.prepareForReuse()
        accessibilityIdentifier = nil
    }

    func updateTheme() {
        rowView.updateTheme()
        discourseCard.updateTheme()
    }

}
