/*****************************************************************************
 * DiscourseHomeTrackCell.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * A track row on the Home screen. It hosts the same DiscourseRowView as the
 * search results, so recently played and top tracks look like every other
 * discourse track row.
 *****************************************************************************/

import UIKit

final class DiscourseHomeTrackCell: UICollectionViewCell {
    static let reuseIdentifier = "DiscourseHomeTrackCell"

    private let rowView = DiscourseRowView()

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
        contentView.backgroundColor = .clear

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

    func configure(with track: DiscourseAudio,
                   isPlaying: Bool,
                   like: DiscourseLikeState,
                   download: DiscourseDownloadState) {
        rowView.configure(with: track,
                          isPlaying: isPlaying,
                          like: like,
                          download: download)
        accessibilityIdentifier = "discourseHomeTrack"
    }

    func configure(with localTrack: DiscourseLocalTrack, isPlaying: Bool) {
        rowView.configure(with: localTrack, isPlaying: isPlaying)
        accessibilityIdentifier = "discourseHomeTrack"
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
