/*****************************************************************************
 * DiscourseMixerTrackCell.swift
 * Rajneesh Discourse
 *
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * One row of the Audio Mixer's track list: artwork, title, duration and a
 * selected checkmark. Reordering and deletion are owned by the table.
 *****************************************************************************/

import AVFoundation
import UIKit

final class DiscourseMixerTrackCell: UITableViewCell {
    static let reuseIdentifier = "DiscourseMixerTrackCell"

    private struct Metadata {
        let artwork: UIImage?
        let duration: String
    }

    private static let metadataCache = NSCache<NSURL, MetadataBox>()

    private final class MetadataBox {
        let metadata: Metadata
        init(_ metadata: Metadata) {
            self.metadata = metadata
        }
    }

    private let containerView = UIView()
    private let gradientLayer = CAGradientLayer()
    private let thumbnailView = VLCArtworkImageView()
    private let titleLabel = UILabel()
    private let durationLabel = UILabel()
    private let checkmarkView = UIView()
    private let checkmarkImageView = UIImageView()
    private var currentURL: URL?
    private var metadataTask: Task<Void, Never>?
    private var isPlaying = false
    private var isSelectedTrack = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        metadataTask?.cancel()
    }

    // MARK: - Setup

    private func setup() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.layer.cornerRadius = 16
        containerView.layer.cornerCurve = .continuous
        containerView.layer.borderWidth = 1
        containerView.clipsToBounds = true
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        containerView.layer.insertSublayer(gradientLayer, at: 0)

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.preferredFont(forTextStyle: .title3).bolded
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail

        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        durationLabel.adjustsFontForContentSizeCategory = true
        durationLabel.text = "--:--"

        checkmarkView.translatesAutoresizingMaskIntoConstraints = false
        checkmarkView.layer.cornerRadius = 15
        checkmarkView.clipsToBounds = true

        checkmarkImageView.translatesAutoresizingMaskIntoConstraints = false
        checkmarkImageView.image = UIImage(systemName: "checkmark",
                                           withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold))
        checkmarkImageView.tintColor = .white
        checkmarkImageView.contentMode = .scaleAspectFit
        checkmarkView.addSubview(checkmarkImageView)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, durationLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 4

        contentView.addSubview(containerView)
        containerView.addSubview(thumbnailView)
        containerView.addSubview(textStack)
        containerView.addSubview(checkmarkView)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),

            thumbnailView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 10),
            thumbnailView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 10),
            thumbnailView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -10),
            thumbnailView.widthAnchor.constraint(equalToConstant: 64),
            thumbnailView.heightAnchor.constraint(equalToConstant: 64),

            textStack.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 14),
            textStack.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: checkmarkView.leadingAnchor, constant: -12),

            checkmarkView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            checkmarkView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            checkmarkView.widthAnchor.constraint(equalToConstant: 30),
            checkmarkView.heightAnchor.constraint(equalToConstant: 30),

            checkmarkImageView.centerXAnchor.constraint(equalTo: checkmarkView.centerXAnchor),
            checkmarkImageView.centerYAnchor.constraint(equalTo: checkmarkView.centerYAnchor),
            checkmarkImageView.widthAnchor.constraint(equalToConstant: 16),
            checkmarkImageView.heightAnchor.constraint(equalToConstant: 16)
        ])

        updateTheme()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = containerView.bounds
        thumbnailView.layer.cornerRadius = 12
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        metadataTask?.cancel()
        metadataTask = nil
        currentURL = nil
        titleLabel.text = nil
        durationLabel.text = "--:--"
        thumbnailView.setImage(nil, placeholderName: nil)
        accessibilityLabel = nil
        isPlaying = false
    }

    // MARK: - Content

    func configure(url: URL, title: String, isSelected: Bool, isPlaying: Bool) {
        currentURL = url
        self.isPlaying = isPlaying
        self.isSelectedTrack = isSelected
        titleLabel.text = title
        durationLabel.text = "--:--"
        thumbnailView.setImage(nil, placeholderName: title)
        checkmarkView.isHidden = !isSelected
        updateAccessibility(title: title)
        updateTheme()
        loadMetadata(for: url)
    }

    private func loadMetadata(for url: URL) {
        metadataTask?.cancel()
        if let cached = Self.metadataCache.object(forKey: url as NSURL) {
            apply(cached.metadata)
            return
        }
        metadataTask = Task { @MainActor [weak self] in
            let metadata = await Self.loadMetadata(for: url)
            guard !Task.isCancelled, let self, self.currentURL == url else { return }
            Self.metadataCache.setObject(MetadataBox(metadata), forKey: url as NSURL)
            self.apply(metadata)
        }
    }

    private func apply(_ metadata: Metadata) {
        thumbnailView.setImage(metadata.artwork, placeholderName: titleLabel.text)
        durationLabel.text = metadata.duration
        updateAccessibility(title: titleLabel.text ?? "")
    }

    private func updateAccessibility(title: String) {
        var value = durationLabel.text ?? ""
        if isPlaying {
            value += ", " + NSLocalizedString("MIXER_ROW_PLAYING",
                                              comment: "Shown on the Audio Mixer track that is playing")
        }
        accessibilityIdentifier = "mixerTrack"
        accessibilityLabel = title
        accessibilityValue = value
    }

    private static func loadMetadata(for url: URL) async -> Metadata {
        let asset = AVURLAsset(url: url)
        var artwork: UIImage?
        if let items = try? await asset.load(.commonMetadata) {
            for item in items where item.commonKey == .commonKeyArtwork {
                if let data = try? await item.load(.dataValue), let image = UIImage(data: data) {
                    artwork = image
                    break
                }
            }
        }
        var durationText = "--:--"
        if let duration = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(duration)
            if seconds.isFinite, seconds > 0 {
                let total = Int(seconds.rounded())
                durationText = String(format: "%02d:%02d", total / 60, total % 60)
            }
        }
        return Metadata(artwork: artwork, duration: durationText)
    }

    // MARK: - Theme

    func updateTheme() {
        let colors = DiscourseColors.current.audioMixer
        if isSelectedTrack {
            gradientLayer.colors = [colors.rowActiveStart.cgColor, colors.rowActiveEnd.cgColor]
            containerView.layer.borderColor = colors.accent.withAlphaComponent(0.7).cgColor
        } else {
            gradientLayer.colors = [colors.rowStart.cgColor, colors.rowEnd.cgColor]
            containerView.layer.borderColor = colors.separator.cgColor
        }
        titleLabel.textColor = colors.text
        durationLabel.textColor = colors.textSecondary
        checkmarkView.backgroundColor = colors.accent
    }
}
