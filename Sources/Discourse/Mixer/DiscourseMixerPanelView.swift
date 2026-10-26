/*****************************************************************************
 * DiscourseMixerPanelView.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * The Audio Mixer's control panel: the follow switch, the current track with a
 * play/pause button, the loop switch and the mixer-only volume. It renders
 * `DiscourseAudioMixer` state and reports intent through closures, so the
 * screen owns every mutation.
 *****************************************************************************/

import UIKit

final class DiscourseMixerPanelView: UIView {
    var onToggleEnabled: ((Bool) -> Void)?
    var onTogglePlayback: (() -> Void)?
    var onToggleLoop: ((Bool) -> Void)?
    var onVolumeChange: ((Int) -> Void)?

    private let cardView = UIView()
    private let contentStack = UIStackView()

    private let enabledSwitch = UISwitch()
    private let enabledLabel = UILabel()
    private let enabledDetailLabel = UILabel()

    private let nowPlayingLabel = UILabel()
    private let trackLabel = UILabel()
    private let playButton = UIButton(type: .system)

    private let loopSwitch = UISwitch()
    private let loopLabel = UILabel()

    private let volumeIconView = UIImageView()
    private let volumeSlider = UISlider()
    private let volumeLabel = UILabel()

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

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.layer.cornerRadius = 16
        cardView.layer.cornerCurve = .continuous
        cardView.layer.borderWidth = 1

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 14

        enabledLabel.text = NSLocalizedString("MIXER_ENABLE_TITLE",
                                              comment: "Switch that makes the Audio Mixer follow the main player")
        enabledLabel.font = UIFont.preferredFont(forTextStyle: .body)
        enabledLabel.adjustsFontForContentSizeCategory = true

        enabledDetailLabel.text = NSLocalizedString("MIXER_ENABLE_DETAIL",
                                                    comment: "Explanation under the Audio Mixer switch")
        enabledDetailLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        enabledDetailLabel.adjustsFontForContentSizeCategory = true
        enabledDetailLabel.numberOfLines = 0

        enabledSwitch.accessibilityLabel = enabledLabel.text
        enabledSwitch.addTarget(self, action: #selector(enabledChanged), for: .valueChanged)

        let enabledText = UIStackView(arrangedSubviews: [enabledLabel, enabledDetailLabel])
        enabledText.axis = .vertical
        enabledText.spacing = 2
        let enabledRow = UIStackView(arrangedSubviews: [enabledText, enabledSwitch])
        enabledRow.axis = .horizontal
        enabledRow.alignment = .center
        enabledRow.spacing = 12

        nowPlayingLabel.text = NSLocalizedString("MIXER_NOW_PLAYING",
                                                 comment: "Caption above the track currently in the Audio Mixer")
        nowPlayingLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        nowPlayingLabel.adjustsFontForContentSizeCategory = true

        trackLabel.font = UIFont.preferredFont(forTextStyle: .body)
        trackLabel.adjustsFontForContentSizeCategory = true
        trackLabel.numberOfLines = 2
        trackLabel.lineBreakMode = .byTruncatingTail

        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        playButton.tintColor = .white
        playButton.layer.cornerRadius = 22
        playButton.layer.cornerCurve = .continuous
        playButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        playButton.heightAnchor.constraint(equalToConstant: 44).isActive = true

        let nowPlayingText = UIStackView(arrangedSubviews: [nowPlayingLabel, trackLabel])
        nowPlayingText.axis = .vertical
        nowPlayingText.spacing = 2
        let nowPlayingRow = UIStackView(arrangedSubviews: [nowPlayingText, playButton])
        nowPlayingRow.axis = .horizontal
        nowPlayingRow.alignment = .center
        nowPlayingRow.spacing = 12

        loopLabel.text = NSLocalizedString("MIXER_LOOP_TITLE",
                                           comment: "Switch that repeats the Audio Mixer's track")
        loopLabel.font = UIFont.preferredFont(forTextStyle: .body)
        loopLabel.adjustsFontForContentSizeCategory = true
        loopSwitch.accessibilityLabel = loopLabel.text
        loopSwitch.addTarget(self, action: #selector(loopChanged), for: .valueChanged)
        let loopRow = UIStackView(arrangedSubviews: [loopLabel, loopSwitch])
        loopRow.axis = .horizontal
        loopRow.alignment = .center
        loopRow.spacing = 12

        volumeIconView.translatesAutoresizingMaskIntoConstraints = false
        volumeIconView.image = UIImage(systemName: "speaker.wave.2")
        volumeIconView.contentMode = .scaleAspectFit
        volumeIconView.setContentHuggingPriority(.required, for: .horizontal)
        volumeIconView.widthAnchor.constraint(equalToConstant: 20).isActive = true

        volumeSlider.minimumValue = Float(DiscourseAudioMixer.minimumVolume)
        volumeSlider.maximumValue = Float(DiscourseAudioMixer.maximumVolume)
        volumeSlider.isContinuous = true
        volumeSlider.accessibilityLabel = NSLocalizedString("MIXER_VOLUME_TITLE",
                                                            comment: "Accessibility label of the Audio Mixer volume slider")
        volumeSlider.addTarget(self, action: #selector(volumeChanged), for: .valueChanged)

        volumeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize,
                                                            weight: .medium)
        volumeLabel.adjustsFontForContentSizeCategory = true
        volumeLabel.textAlignment = .right
        volumeLabel.setContentHuggingPriority(.required, for: .horizontal)
        volumeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true

        let volumeRow = UIStackView(arrangedSubviews: [volumeIconView, volumeSlider, volumeLabel])
        volumeRow.axis = .horizontal
        volumeRow.alignment = .center
        volumeRow.spacing = 10

        contentStack.addArrangedSubview(enabledRow)
        contentStack.addArrangedSubview(nowPlayingRow)
        contentStack.addArrangedSubview(loopRow)
        contentStack.addArrangedSubview(volumeRow)

        addSubview(cardView)
        cardView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: topAnchor),
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

            contentStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16)
        ])

        updateTheme()
    }

    // MARK: - Content

    func configure(enabled: Bool,
                   isPlaying: Bool,
                   title: String?,
                   isLooping: Bool,
                   volume: Int,
                   hasSelection: Bool) {
        enabledSwitch.setOn(enabled, animated: false)
        loopSwitch.setOn(isLooping, animated: false)

        let placeholder = NSLocalizedString("MIXER_NO_TRACK",
                                            comment: "Shown in the Audio Mixer panel when no track is selected")
        trackLabel.text = title ?? placeholder
        trackLabel.alpha = title == nil ? 0.6 : 1
        playButton.isEnabled = hasSelection
        updatePlayButton(isPlaying: isPlaying)
        playButton.alpha = hasSelection ? 1 : 0.4

        volumeSlider.value = Float(volume)
        volumeLabel.text = String(format: "%d%%", volume)
        volumeSlider.accessibilityValue = volumeLabel.text

        updateTheme()
    }

    private func updatePlayButton(isPlaying: Bool) {
        let symbol = isPlaying ? "pause.fill" : "play.fill"
        playButton.setImage(UIImage(systemName: symbol,
                                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 16,
                                                                                   weight: .bold)),
                            for: .normal)
        playButton.accessibilityLabel = isPlaying
            ? NSLocalizedString("MIXER_PAUSE_ACCESSIBILITY",
                                comment: "Accessibility label of the Audio Mixer pause button")
            : NSLocalizedString("MIXER_PLAY_ACCESSIBILITY",
                                comment: "Accessibility label of the Audio Mixer play button")
    }

    // MARK: - Actions

    @objc private func enabledChanged() {
        onToggleEnabled?(enabledSwitch.isOn)
    }

    @objc private func loopChanged() {
        onToggleLoop?(loopSwitch.isOn)
    }

    @objc private func playTapped() {
        onTogglePlayback?()
    }

    @objc private func volumeChanged() {
        let value = Int(volumeSlider.value.rounded())
        volumeLabel.text = String(format: "%d%%", value)
        volumeSlider.accessibilityValue = volumeLabel.text
        onVolumeChange?(value)
    }

    // MARK: - Theme

    func updateTheme() {
        let colors = DiscourseColors.current
        cardView.backgroundColor = colors.trackSurface
        cardView.layer.borderColor = colors.trackBorder.cgColor
        enabledLabel.textColor = colors.primaryText
        enabledDetailLabel.textColor = colors.secondaryText
        nowPlayingLabel.textColor = colors.secondaryText
        trackLabel.textColor = colors.primaryText
        loopLabel.textColor = colors.primaryText
        playButton.backgroundColor = colors.accent
        volumeIconView.tintColor = colors.secondaryText
        volumeLabel.textColor = colors.secondaryText
        volumeSlider.minimumTrackTintColor = colors.accent
        volumeSlider.maximumTrackTintColor = colors.divider
        enabledSwitch.onTintColor = colors.accent
        loopSwitch.onTintColor = colors.accent
    }
}
