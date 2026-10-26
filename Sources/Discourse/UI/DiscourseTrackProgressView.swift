/*****************************************************************************
 * DiscourseTrackProgressView.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * The leading badge of a track row: the track number inside a progress ring,
 * a speaker while it plays and a checkmark once it finished. The ring is drawn
 * with core animation, so updating the fraction on every store change is cheap.
 *****************************************************************************/

import UIKit

final class DiscourseTrackProgressView: UIView {
    private let trackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()
    private let label = UILabel()
    private let checkmarkView = UIImageView()
    private let speakerView = UIImageView()

    private var fraction: CGFloat = 0
    private var isCompleted = false

    init() {
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: 26, height: 26)
    }

    // MARK: - Setup

    private func setup() {
        backgroundColor = .clear
        isAccessibilityElement = false

        trackLayer.fillColor = UIColor.clear.cgColor
        trackLayer.lineWidth = 2
        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.lineWidth = 2
        progressLayer.lineCap = .round
        layer.addSublayer(trackLayer)
        layer.addSublayer(progressLayer)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.monospacedDigitSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .caption2).pointSize,
                                                      weight: .regular)
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center

        let configuration = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        checkmarkView.image = UIImage(systemName: "checkmark", withConfiguration: configuration)
        checkmarkView.translatesAutoresizingMaskIntoConstraints = false
        checkmarkView.contentMode = .scaleAspectFit
        checkmarkView.isHidden = true

        speakerView.image = UIImage(systemName: "speaker.wave.2.fill", withConfiguration: configuration)
        speakerView.translatesAutoresizingMaskIntoConstraints = false
        speakerView.contentMode = .scaleAspectFit
        speakerView.isHidden = true

        addSubview(label)
        addSubview(checkmarkView)
        addSubview(speakerView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 26),
            heightAnchor.constraint(equalToConstant: 26),

            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -2),

            checkmarkView.centerXAnchor.constraint(equalTo: centerXAnchor),
            checkmarkView.centerYAnchor.constraint(equalTo: centerYAnchor),
            speakerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            speakerView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateTheme()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let insetRect = bounds.insetBy(dx: 3, dy: 3)
        let path = UIBezierPath(ovalIn: insetRect).cgPath
        trackLayer.frame = bounds
        progressLayer.frame = bounds
        trackLayer.path = path
        progressLayer.path = path

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.strokeStart = 0
        progressLayer.strokeEnd = isCompleted ? 1 : fraction
        CATransaction.commit()
    }

    // MARK: - Content

    func configure(position: Int, fraction: Double, isCompleted: Bool, isPlaying: Bool) {
        label.text = "\(position)"
        self.fraction = CGFloat(min(max(fraction, 0), 1))
        self.isCompleted = isCompleted

        label.isHidden = isPlaying || isCompleted
        speakerView.isHidden = !isPlaying
        checkmarkView.isHidden = !isCompleted || isPlaying
        trackLayer.isHidden = isPlaying || isCompleted
        progressLayer.isHidden = isPlaying || isCompleted

        setNeedsLayout()
        updateTheme()
    }

    // MARK: - Theme

    func updateTheme() {
        let colors = DiscourseColors.current
        trackLayer.strokeColor = colors.trackBorder.cgColor
        progressLayer.strokeColor = colors.accent.cgColor
        label.textColor = colors.trackSecondaryText
        checkmarkView.tintColor = colors.accent
        speakerView.tintColor = colors.accent
    }
}
