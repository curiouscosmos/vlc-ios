/*****************************************************************************
 * DiscourseDownloadControl.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * The per-track download affordance for track rows: an outlined arrow when the
 * track streams, a determinate ring while it downloads, a filled green arrow
 * once the file is verified on disk, and an exclamation when the last attempt
 * failed. Tapping downloads, cancels, retries or removes a completed download.
 * Like `DiscourseLikeControl`, it is a
 * pure renderer of `DiscourseDownloadState` and the hosting screen owns the
 * action.
 *****************************************************************************/

import UIKit

/// Downloaded/active counts for one discourse, shown on catalogue and Home
/// cards. The Home carousel has a fixed height, so its tiles show the counts in
/// a badge over the artwork; the catalogue's full-width list row puts the same
/// badge in its footer instead of resizing.
struct DiscourseDownloadSummary: Equatable {
    let downloaded: Int
    let active: Int
    let total: Int

    var isVisible: Bool {
        return downloaded > 0 || active > 0
    }

    /// "3/11": finished tracks, or running ones when nothing is finished yet.
    var text: String {
        let count = downloaded > 0 ? downloaded : active
        return "\(count)/\(max(total, count))"
    }

    var accessibilityLabel: String {
        if downloaded > 0 {
            return String(format: NSLocalizedString("DISCOURSE_DOWNLOADS_COUNT_ACCESSIBILITY",
                                                    comment: "Accessibility label of the card download badge: downloaded tracks, total tracks"),
                          downloaded, total)
        }
        return String(format: NSLocalizedString("DISCOURSE_DOWNLOADS_ACTIVE_ACCESSIBILITY",
                                                comment: "Accessibility label of the card download badge while tracks download: active tracks, total tracks"),
                      active, total)
    }

    var isDownloading: Bool {
        return active > 0
    }

    static func resolve(discourseID: String,
                        totalTracks: Int,
                        store: DiscourseDownloadStore = .shared,
                        manager: DiscourseDownloadManager = .shared) -> DiscourseDownloadSummary {
        return DiscourseDownloadSummary(downloaded: store.downloadedCount(forDiscourse: discourseID),
                                        active: manager.activeCount(forDiscourse: discourseID),
                                        total: max(0, totalTracks))
    }
}

final class DiscourseDownloadControl: UIControl {
    private let iconView = UIImageView()
    private let ringTrackLayer = CAShapeLayer()
    private let ringProgressLayer = CAShapeLayer()

    private var downloadState: DiscourseDownloadState = .missing
    private var trackTitle = ""

    override var isEnabled: Bool {
        didSet { updateTheme() }
    }

    private let iconSize: CGFloat
    /// Player actions sit on artwork, where the muted row treatment disappears.
    private let highContrastIcon: Bool
    private var symbolConfiguration: UIImage.SymbolConfiguration {
        return UIImage.SymbolConfiguration(pointSize: iconSize - 3, weight: .semibold)
    }
    private static let ringSize: CGFloat = 22

    init(iconSize: CGFloat = 18, highContrastIcon: Bool = false) {
        self.iconSize = iconSize
        self.highContrastIcon = highContrastIcon
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: Self.ringSize, height: Self.ringSize)
    }

    /// The glyph is small on purpose; keep the touch target at least 44 pt.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let dx = min(0, (bounds.width - 44) / 2)
        let dy = min(0, (bounds.height - 44) / 2)
        return bounds.insetBy(dx: dx, dy: dy).contains(point)
    }

    // MARK: - Setup

    private func setup() {
        isAccessibilityElement = true
        accessibilityTraits = .button

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.isUserInteractionEnabled = false
        addSubview(iconView)

        for layer in [ringTrackLayer, ringProgressLayer] {
            layer.fillColor = UIColor.clear.cgColor
            layer.lineWidth = 2.5
            layer.lineCap = .round
            layer.strokeEnd = 0
        }
        ringTrackLayer.strokeEnd = 1
        layer.addSublayer(ringTrackLayer)
        layer.addSublayer(ringProgressLayer)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize)
        ])

        updateTheme()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let side = min(bounds.width, bounds.height)
        let ringBounds = CGRect(x: (bounds.width - side) / 2,
                                y: (bounds.height - side) / 2,
                                width: side,
                                height: side)
        let radius = (side - ringTrackLayer.lineWidth) / 2
        let center = CGPoint(x: ringBounds.midX, y: ringBounds.midY)
        let path = UIBezierPath(arcCenter: center,
                                radius: radius,
                                startAngle: -.pi / 2,
                                endAngle: .pi * 3 / 2,
                                clockwise: true)
        ringTrackLayer.frame = bounds
        ringProgressLayer.frame = bounds
        ringTrackLayer.path = path.cgPath
        ringProgressLayer.path = path.cgPath
    }

    // MARK: - Content

    func configure(with state: DiscourseDownloadState, title: String) {
        downloadState = state
        trackTitle = title

        switch downloadState {
        case .missing:
            iconView.isHidden = false
            setRingVisible(false)
            iconView.image = UIImage(systemName: "arrow.down.circle",
                                     withConfiguration: symbolConfiguration)
        case .downloading(let progress):
            iconView.isHidden = true
            setRingVisible(true)
            ringProgressLayer.strokeEnd = CGFloat(min(1, max(0, progress)))
        case .downloaded:
            iconView.isHidden = false
            setRingVisible(false)
            iconView.image = UIImage(systemName: "arrow.down.circle.fill",
                                     withConfiguration: symbolConfiguration)
        case .failed:
            iconView.isHidden = false
            setRingVisible(false)
            iconView.image = UIImage(systemName: "exclamationmark.circle",
                                     withConfiguration: symbolConfiguration)
        }

        updateAccessibility()
        updateTheme()
    }

    private func setRingVisible(_ visible: Bool) {
        ringTrackLayer.isHidden = !visible
        ringProgressLayer.isHidden = !visible
    }

    // MARK: - State

    override var isHighlighted: Bool {
        didSet {
            alpha = isHighlighted ? 0.5 : 1
        }
    }

    // MARK: - Accessibility

    private func updateAccessibility() {
        let trimmed = trackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        switch downloadState {
        case .missing:
            accessibilityLabel = String(format: NSLocalizedString("DISCOURSE_DOWNLOAD_ACCESSIBILITY",
                                                                  comment: "Accessibility label of a track that can be downloaded: track title"),
                                        trimmed)
            accessibilityValue = nil
        case .downloading(let progress):
            accessibilityLabel = String(format: NSLocalizedString("DISCOURSE_DOWNLOAD_CANCEL_ACCESSIBILITY",
                                                                  comment: "Accessibility label of a track download in progress: track title"),
                                        trimmed)
            accessibilityValue = String(format: "%d%%", Int((min(1, max(0, progress)) * 100).rounded()))
        case .downloaded:
            accessibilityLabel = NSLocalizedString("DISCOURSE_DOWNLOAD_REMOVE_MENU",
                                                   comment: "Delete a downloaded track") + ", " + trimmed
            accessibilityValue = nil
        case .failed:
            accessibilityLabel = String(format: NSLocalizedString("DISCOURSE_DOWNLOAD_FAILED_ACCESSIBILITY",
                                                                  comment: "Accessibility label of a failed track download: track title"),
                                        trimmed)
            accessibilityValue = nil
        }

        accessibilityTraits = .button
    }

    // MARK: - Theme

    func updateTheme() {
        let colors = DiscourseColors.current
        ringTrackLayer.strokeColor = colors.divider.cgColor
        ringProgressLayer.strokeColor = colors.accent.cgColor

        switch downloadState {
        case .missing:
            if !isEnabled && !colors.isDark {
                iconView.tintColor = colors.accent
            } else if highContrastIcon && colors.isDark {
                iconView.tintColor = .white
            } else {
                iconView.tintColor = colors.secondaryText
            }
        case .downloading:
            iconView.tintColor = colors.accent
        case .downloaded:
            iconView.tintColor = colors.downloaded
        case .failed:
            iconView.tintColor = colors.likedHeart
        }
    }
}
