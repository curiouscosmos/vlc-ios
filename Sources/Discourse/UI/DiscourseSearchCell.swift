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

        rowView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rowView)

        NSLayoutConstraint.activate([
            rowView.topAnchor.constraint(equalTo: contentView.topAnchor),
            rowView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            rowView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            rowView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    // MARK: - Content

    var onOpen: (() -> Void)? {
        get { rowView.onOpen }
        set { rowView.onOpen = newValue }
    }

    var onToggleLike: (() -> Void)? {
        get { rowView.onToggleLike }
        set { rowView.onToggleLike = newValue }
    }

    var onToggleDownload: (() -> Void)? {
        get { rowView.onToggleDownload }
        set { rowView.onToggleDownload = newValue }
    }

    func configure(with discourse: Discourse, like: DiscourseLikeState) {
        rowView.configure(with: discourse, like: like)
        accessibilityIdentifier = "discourseSearchDiscourse"
    }

    func configure(with track: DiscourseAudio,
                   isPlaying: Bool,
                   like: DiscourseLikeState,
                   download: DiscourseDownloadState) {
        rowView.configure(with: track,
                          isPlaying: isPlaying,
                          like: like,
                          download: download)
        accessibilityIdentifier = "discourseSearchTrack"
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        rowView.prepareForReuse()
        accessibilityIdentifier = nil
    }

    func updateTheme() {
        rowView.updateTheme()
    }

}
