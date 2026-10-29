/*****************************************************************************
 * DiscourseMixerPanelView.swift
 * Rajneesh Discourse
 *
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * The Audio Mixer's control card: play/pause, status, loop and the mixer-only
 * volume. It renders `DiscourseAudioMixer` state and reports intent through
 * closures, so the screen owns every mutation.
 *****************************************************************************/

import UIKit

final class DiscourseMixerPanelView: UIView {
    var onTogglePlayback: (() -> Void)?
    var onToggleEnabled: ((Bool) -> Void)?
    var onToggleLoop: ((Bool) -> Void)?
    var onVolumeChange: ((Int) -> Void)?
    private let cardView = UIView()
    private let grabberView = UIView()
    private let playButton = UIButton(type: .custom)
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let enabledToggleButton = UIButton(type: .custom)
    private let loopButton = UIButton(type: .system)
    private let volumeCard = UIView()
    private let volumeTitle = UILabel()
    private let volumeLabel = UILabel()
    private let volumeSlider = UISlider()
    private let minusButton = UIButton(type: .system)
    private let plusButton = UIButton(type: .system)
    private var enabled = false
    private var looping = false
    private var isPlaying = false
    private var volume = DiscourseAudioMixer.defaultVolume

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setup() {
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.layer.cornerRadius = 24
        cardView.layer.cornerCurve = .continuous
        cardView.layer.borderWidth = 1

        grabberView.translatesAutoresizingMaskIntoConstraints = false
        grabberView.layer.cornerRadius = 2

        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.layer.cornerRadius = 30
        playButton.clipsToBounds = true
        playButton.accessibilityIdentifier = "discourseMixerEnabled"
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.preferredFont(forTextStyle: .title3).bolded
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.numberOfLines = 2

        enabledToggleButton.translatesAutoresizingMaskIntoConstraints = false
        enabledToggleButton.backgroundColor = .clear
        enabledToggleButton.accessibilityLabel = NSLocalizedString("MIXER_TOGGLE_ACCESSIBILITY",
                                                                    value: "Turn mixer on or off",
                                                                    comment: "Mixer on/off toggle")
        enabledToggleButton.accessibilityIdentifier = "discourseMixerToggle"
        enabledToggleButton.addTarget(self, action: #selector(enabledTapped), for: .touchUpInside)

        loopButton.translatesAutoresizingMaskIntoConstraints = false
        loopButton.accessibilityLabel = NSLocalizedString("MIXER_LOOP_TITLE", comment: "Loop mixer track")
        loopButton.accessibilityIdentifier = "discourseMixerLoop"
        loopButton.addTarget(self, action: #selector(loopTapped), for: .touchUpInside)

        volumeCard.translatesAutoresizingMaskIntoConstraints = false
        volumeCard.layer.cornerRadius = 16
        volumeCard.layer.cornerCurve = .continuous

        volumeTitle.translatesAutoresizingMaskIntoConstraints = false
        volumeTitle.font = UIFont.preferredFont(forTextStyle: .subheadline)
        volumeTitle.adjustsFontForContentSizeCategory = true
        volumeTitle.text = NSLocalizedString("MIXER_VOLUME_TITLE", comment: "Mixer volume")

        volumeLabel.translatesAutoresizingMaskIntoConstraints = false
        volumeLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        volumeLabel.adjustsFontForContentSizeCategory = true
        volumeLabel.textAlignment = .right

        volumeSlider.translatesAutoresizingMaskIntoConstraints = false
        volumeSlider.minimumValue = Float(DiscourseAudioMixer.minimumVolume)
        volumeSlider.maximumValue = Float(DiscourseAudioMixer.maximumVolume)
        volumeSlider.accessibilityLabel = volumeTitle.text
        volumeSlider.addTarget(self, action: #selector(volumeChanged), for: .valueChanged)

        minusButton.translatesAutoresizingMaskIntoConstraints = false
        minusButton.accessibilityLabel = NSLocalizedString("MIXER_VOLUME_DECREASE",
                                                           value: "Decrease mixer volume",
                                                           comment: "Volume button")
        minusButton.addTarget(self, action: #selector(stepVolume(_:)), for: .touchUpInside)
        plusButton.translatesAutoresizingMaskIntoConstraints = false
        plusButton.accessibilityLabel = NSLocalizedString("MIXER_VOLUME_INCREASE",
                                                          value: "Increase mixer volume",
                                                          comment: "Volume button")
        plusButton.addTarget(self, action: #selector(stepVolume(_:)), for: .touchUpInside)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, statusLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 3

        let volumeLabels = UIStackView(arrangedSubviews: [volumeTitle, volumeLabel])
        volumeLabels.translatesAutoresizingMaskIntoConstraints = false
        volumeLabels.axis = .horizontal
        volumeLabels.spacing = 8
        volumeLabels.alignment = .firstBaseline
        volumeLabel.setContentHuggingPriority(.required, for: .horizontal)

        let sliderRow = UIStackView(arrangedSubviews: [minusButton, volumeSlider, plusButton])
        sliderRow.translatesAutoresizingMaskIntoConstraints = false
        sliderRow.axis = .horizontal
        sliderRow.spacing = 10
        sliderRow.alignment = .center

        addSubview(cardView)
        cardView.addSubview(grabberView)
        cardView.addSubview(playButton)
        cardView.addSubview(textStack)
        cardView.addSubview(enabledToggleButton)
        cardView.addSubview(loopButton)
        cardView.addSubview(volumeCard)
        volumeCard.addSubview(volumeLabels)
        volumeCard.addSubview(sliderRow)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: topAnchor),
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor),

            grabberView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 8),
            grabberView.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            grabberView.widthAnchor.constraint(equalToConstant: 40),
            grabberView.heightAnchor.constraint(equalToConstant: 4),

            playButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 20),
            playButton.topAnchor.constraint(equalTo: grabberView.bottomAnchor, constant: 14),
            playButton.widthAnchor.constraint(equalToConstant: 60),
            playButton.heightAnchor.constraint(equalToConstant: 60),

            textStack.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: 14),
            textStack.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: loopButton.leadingAnchor, constant: -10),

            enabledToggleButton.leadingAnchor.constraint(equalTo: textStack.leadingAnchor),
            enabledToggleButton.trailingAnchor.constraint(equalTo: textStack.trailingAnchor),
            enabledToggleButton.topAnchor.constraint(equalTo: textStack.topAnchor),
            enabledToggleButton.bottomAnchor.constraint(equalTo: textStack.bottomAnchor),

            loopButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -20),
            loopButton.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            loopButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),

            volumeCard.topAnchor.constraint(equalTo: playButton.bottomAnchor, constant: 14),
            volumeCard.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            volumeCard.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            volumeCard.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -14),

            volumeLabels.topAnchor.constraint(equalTo: volumeCard.topAnchor, constant: 12),
            volumeLabels.leadingAnchor.constraint(equalTo: volumeCard.leadingAnchor, constant: 16),
            volumeLabels.trailingAnchor.constraint(equalTo: volumeCard.trailingAnchor, constant: -16),

            sliderRow.topAnchor.constraint(equalTo: volumeLabels.bottomAnchor, constant: 8),
            sliderRow.leadingAnchor.constraint(equalTo: volumeCard.leadingAnchor, constant: 12),
            sliderRow.trailingAnchor.constraint(equalTo: volumeCard.trailingAnchor, constant: -12),
            sliderRow.bottomAnchor.constraint(equalTo: volumeCard.bottomAnchor, constant: -12),

            minusButton.widthAnchor.constraint(equalToConstant: 36),
            minusButton.heightAnchor.constraint(equalToConstant: 36),
            plusButton.widthAnchor.constraint(equalToConstant: 36),
            plusButton.heightAnchor.constraint(equalToConstant: 36)
        ])

        updateTheme()
    }

    // MARK: - Configuration

    func configure(enabled: Bool, isPlaying: Bool, isLooping: Bool, volume: Int) {
        self.enabled = enabled
        self.isPlaying = isPlaying
        self.looping = isLooping
        self.volume = volume

        titleLabel.text = enabled
            ? NSLocalizedString("MIXER_ENABLE_TITLE", comment: "Mixer on")
            : NSLocalizedString("MIXER_DISABLED_TITLE", value: "Mixer off", comment: "Mixer disabled")
        if !enabled {
            statusLabel.text = NSLocalizedString("MIXER_STATUS_OFF",
                                                 value: "Background music is off",
                                                 comment: "Mixer status when disabled")
        } else if isPlaying {
            statusLabel.text = NSLocalizedString("MIXER_STATUS_PLAYING",
                                                 value: "Background music is playing",
                                                 comment: "Mixer status while playing")
        } else {
            statusLabel.text = NSLocalizedString("MIXER_STATUS_WAITING",
                                                 value: "Waiting for playback",
                                                 comment: "Mixer status while waiting for the main player")
        }

        let playTitle = isPlaying
            ? NSLocalizedString("MIXER_PAUSE_ACCESSIBILITY", comment: "Pause mixer")
            : NSLocalizedString("MIXER_PLAY_ACCESSIBILITY", comment: "Play mixer")
        playButton.accessibilityLabel = playTitle
        playButton.accessibilityValue = enabled ? "On" : "Off"
        enabledToggleButton.accessibilityValue = enabled ? "On" : "Off"

        var loop = UIButton.Configuration.plain()
        loop.title = NSLocalizedString("MIXER_LOOP_BUTTON", value: "Loop", comment: "Loop button")
        loop.image = UIImage(systemName: "repeat")
        loop.imagePadding = 6
        loop.cornerStyle = .capsule
        loop.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14)
        loop.background.cornerRadius = 20
        loop.background.strokeWidth = 1
        loopButton.configuration = loop
        loopButton.accessibilityValue = isLooping ? "On" : "Off"

        volumeSlider.value = Float(volume)
        volumeLabel.text = String(format: "%d%%", volume)
        volumeSlider.accessibilityValue = volumeLabel.text

        updateTheme()
    }

    // MARK: - Actions

    @objc private func playTapped() {
        onTogglePlayback?()
    }

    @objc private func enabledTapped() {
        onToggleEnabled?(!enabled)
    }

    @objc private func loopTapped() {
        onToggleLoop?(!looping)
    }

    @objc private func stepVolume(_ sender: UIButton) {
        volumeSlider.value += sender === plusButton ? 1 : -1
        volumeChanged()
    }

    @objc private func volumeChanged() {
        let value = Int(volumeSlider.value.rounded())
        volumeLabel.text = String(format: "%d%%", value)
        volumeSlider.accessibilityValue = volumeLabel.text
        onVolumeChange?(value)
    }

    // MARK: - Theme

    func updateTheme() {
        let colors = DiscourseColors.current.audioMixer
        cardView.backgroundColor = colors.card
        cardView.layer.borderColor = colors.cardBorder.cgColor
        grabberView.backgroundColor = colors.separator

        playButton.backgroundColor = colors.accent
        playButton.tintColor = .white
        updatePlayIcon()

        titleLabel.textColor = colors.text
        statusLabel.textColor = colors.textSecondary

        loopButton.tintColor = colors.accent
        loopButton.configuration?.baseForegroundColor = looping ? colors.accent : colors.textSecondary
        loopButton.configuration?.baseBackgroundColor = looping
            ? colors.accent.withAlphaComponent(0.12)
            : .clear
        loopButton.configuration?.background.strokeColor = looping ? colors.accent : colors.separator

        volumeCard.backgroundColor = colors.rowEnd
        volumeCard.layer.borderWidth = 1
        volumeCard.layer.borderColor = colors.separator.cgColor
        volumeTitle.textColor = colors.textSecondary
        volumeLabel.textColor = colors.textSecondary

        volumeSlider.minimumTrackTintColor = colors.accent
        volumeSlider.maximumTrackTintColor = colors.sliderInactive
        volumeSlider.thumbTintColor = colors.accent
        volumeSlider.setThumbImage(Self.circleImage(diameter: 28, color: colors.accent), for: .normal)
        volumeSlider.setThumbImage(Self.circleImage(diameter: 28, color: colors.accent), for: .highlighted)

        for button in [minusButton, plusButton] {
            var config = UIButton.Configuration.plain()
            config.image = UIImage(systemName: button === plusButton ? "plus" : "minus")
            config.baseForegroundColor = colors.accent
            config.background.strokeColor = colors.separator
            config.background.strokeWidth = 1
            config.background.cornerRadius = 18
            config.contentInsets = .zero
            button.configuration = config
        }
    }

    private func updatePlayIcon() {
        let symbol = isPlaying ? "pause.fill" : "play.fill"
        let configuration = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        playButton.setImage(UIImage(systemName: symbol, withConfiguration: configuration), for: .normal)
    }

    private static func circleImage(diameter: CGFloat, color: UIColor) -> UIImage {
        let size = CGSize(width: diameter, height: diameter)
        return UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
        }
    }
}
