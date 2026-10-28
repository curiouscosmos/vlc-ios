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
 * The Audio Mixer's collapsible control card: enable, loop, playback menu
 * and mixer-only volume. It renders
 * `DiscourseAudioMixer` state and reports intent through closures, so the
 * screen owns every mutation.
 *****************************************************************************/

import UIKit

final class DiscourseMixerPanelView: UIView {
    var onToggleEnabled: ((Bool) -> Void)?
    var onTogglePlayback: (() -> Void)?
    var onToggleLoop: ((Bool) -> Void)?
    var onVolumeChange: ((Int) -> Void)?
    var onLayoutChange: (() -> Void)?

    private let cardView = UIView()
    private let contentStack = UIStackView()
    private let controlsStack = UIStackView()
    private let headingButton = UIButton(type: .system)
    private let enabledButton = UIButton(type: .system)
    private let loopButton = UIButton(type: .system)
    private let menuButton = UIButton(type: .system)
    private let volumeTitle = UILabel()
    private let volumeLabel = UILabel()
    private let volumeSlider = UISlider()
    private let minusButton = UIButton(type: .system)
    private let plusButton = UIButton(type: .system)
    private var enabled = false
    private var looping = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        cardView.layer.cornerRadius = 16
        cardView.layer.cornerCurve = .continuous
        cardView.layer.borderWidth = 1
        contentStack.axis = .vertical
        contentStack.spacing = 16
        controlsStack.axis = .vertical
        controlsStack.spacing = 12

        var heading = UIButton.Configuration.plain()
        heading.title = NSLocalizedString("MIXER_PANEL_TITLE", value: "Background Music Mixer", comment: "Mixer card heading")
        heading.image = UIImage(systemName: "slider.horizontal.3")
        heading.imagePadding = 12
        heading.contentInsets = .zero
        heading.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFont.preferredFont(forTextStyle: .headline)
            return attributes
        }
        headingButton.configuration = heading
        headingButton.contentHorizontalAlignment = .leading
        headingButton.addTarget(self, action: #selector(toggleExpanded), for: .touchUpInside)
        let chevron = UIImageView(image: UIImage(systemName: "chevron.up"))
        chevron.tag = 1
        chevron.contentMode = .scaleAspectFit
        headingButton.addSubview(chevron)
        chevron.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            chevron.trailingAnchor.constraint(equalTo: headingButton.trailingAnchor),
            chevron.centerYAnchor.constraint(equalTo: headingButton.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 16)
        ])
        headingButton.configuration?.contentInsets.trailing = 24

        enabledButton.accessibilityIdentifier = "discourseMixerEnabled"
        enabledButton.addTarget(self, action: #selector(enabledChanged), for: .touchUpInside)
        loopButton.accessibilityLabel = NSLocalizedString("MIXER_LOOP_TITLE", comment: "Loop mixer track")
        loopButton.addTarget(self, action: #selector(loopChanged), for: .touchUpInside)
        menuButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        menuButton.transform = CGAffineTransform(rotationAngle: .pi / 2)
        menuButton.accessibilityLabel = NSLocalizedString("MORE_OPTIONS", value: "More options", comment: "Mixer options")
        menuButton.showsMenuAsPrimaryAction = true
        let buttons = UIStackView(arrangedSubviews: [enabledButton, loopButton, menuButton])
        buttons.spacing = 8
        enabledButton.widthAnchor.constraint(equalTo: loopButton.widthAnchor).isActive = true
        menuButton.widthAnchor.constraint(equalToConstant: 44).isActive = true

        volumeTitle.text = NSLocalizedString("MIXER_VOLUME_TITLE", comment: "Mixer volume")
        for label in [volumeTitle, volumeLabel] {
            label.font = UIFont.preferredFont(forTextStyle: .subheadline)
            label.adjustsFontForContentSizeCategory = true
        }
        volumeLabel.textAlignment = .right
        let labels = UIStackView(arrangedSubviews: [volumeTitle, volumeLabel])
        labels.spacing = 8
        volumeSlider.minimumValue = Float(DiscourseAudioMixer.minimumVolume)
        volumeSlider.maximumValue = Float(DiscourseAudioMixer.maximumVolume)
        volumeSlider.accessibilityLabel = volumeTitle.text
        volumeSlider.addTarget(self, action: #selector(volumeChanged), for: .valueChanged)
        minusButton.setImage(UIImage(systemName: "minus"), for: .normal)
        plusButton.setImage(UIImage(systemName: "plus"), for: .normal)
        minusButton.accessibilityLabel = NSLocalizedString("MIXER_VOLUME_DECREASE", value: "Decrease mixer volume", comment: "Volume button")
        plusButton.accessibilityLabel = NSLocalizedString("MIXER_VOLUME_INCREASE", value: "Increase mixer volume", comment: "Volume button")
        minusButton.addTarget(self, action: #selector(stepVolume(_:)), for: .touchUpInside)
        plusButton.addTarget(self, action: #selector(stepVolume(_:)), for: .touchUpInside)
        let sliderRow = UIStackView(arrangedSubviews: [minusButton, volumeSlider, plusButton])
        sliderRow.spacing = 12
        sliderRow.alignment = .center
        for button in [headingButton, enabledButton, loopButton, minusButton, plusButton] {
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        }
        for button in [minusButton, plusButton] {
            button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        }
        [buttons, labels, sliderRow].forEach { controlsStack.addArrangedSubview($0) }
        [headingButton, controlsStack].forEach { contentStack.addArrangedSubview($0) }
        addSubview(cardView)
        cardView.addSubview(contentStack)
        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: topAnchor),
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            contentStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            contentStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            contentStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12)
        ])
        updateTheme()
    }

    func configure(enabled: Bool, isPlaying: Bool, title: String?, isLooping: Bool,
                   volume: Int, hasSelection: Bool) {
        self.enabled = enabled
        looping = isLooping
        var primary = UIButton.Configuration.filled()
        primary.title = enabled
            ? NSLocalizedString("MIXER_ENABLE_TITLE", comment: "Mixer on")
            : NSLocalizedString("MIXER_DISABLED_TITLE", value: "Mixer off", comment: "Mixer disabled")
        primary.image = UIImage(systemName: isPlaying ? "pause.circle" : "play.circle")
        primary.imagePadding = 8
        primary.cornerStyle = .small
        enabledButton.configuration = primary
        enabledButton.accessibilityValue = enabled ? "1" : "0"
        var loop = UIButton.Configuration.bordered()
        loop.title = NSLocalizedString("MIXER_LOOP_BUTTON", value: "Loop", comment: "Loop button")
        loop.image = UIImage(systemName: "repeat")
        loop.imagePadding = 8
        loop.cornerStyle = .small
        loop.background.strokeWidth = 1
        loopButton.configuration = loop
        loopButton.accessibilityValue = isLooping ? "1" : "0"
        let playTitle = isPlaying
            ? NSLocalizedString("MIXER_PAUSE_ACCESSIBILITY", comment: "Pause mixer")
            : NSLocalizedString("MIXER_PLAY_ACCESSIBILITY", comment: "Play mixer")
        menuButton.menu = UIMenu(title: title ?? NSLocalizedString("MIXER_NO_TRACK", comment: "No track"), children: [
            UIAction(title: playTitle, image: UIImage(systemName: isPlaying ? "pause" : "play"),
                     attributes: hasSelection ? [] : .disabled) { [weak self] _ in self?.onTogglePlayback?() }
        ])
        volumeSlider.value = Float(volume)
        volumeLabel.text = String(format: "%d%%", volume)
        volumeSlider.accessibilityValue = volumeLabel.text
        updateTheme()
    }

    @objc private func toggleExpanded() {
        controlsStack.isHidden.toggle()
        (headingButton.viewWithTag(1) as? UIImageView)?.image = UIImage(systemName: controlsStack.isHidden ? "chevron.down" : "chevron.up")
        onLayoutChange?()
    }

    @objc private func enabledChanged() { onToggleEnabled?(!enabled) }
    @objc private func loopChanged() { onToggleLoop?(!looping) }

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

    func updateTheme() {
        let colors = DiscourseColors.current
        cardView.backgroundColor = colors.trackSurface
        cardView.layer.borderColor = colors.trackBorder.cgColor
        headingButton.tintColor = colors.accent
        headingButton.configuration?.baseForegroundColor = colors.primaryText
        enabledButton.configuration?.baseBackgroundColor = colors.accent
        enabledButton.configuration?.baseForegroundColor = .white
        loopButton.configuration?.baseForegroundColor = colors.accent
        loopButton.configuration?.baseBackgroundColor = looping ? colors.accent.withAlphaComponent(0.1) : .clear
        loopButton.configuration?.background.strokeColor = colors.accent
        menuButton.tintColor = colors.secondaryText
        minusButton.tintColor = colors.accent
        plusButton.tintColor = colors.accent
        volumeTitle.textColor = colors.secondaryText
        volumeLabel.textColor = colors.secondaryText
        volumeSlider.minimumTrackTintColor = colors.accent
        volumeSlider.maximumTrackTintColor = colors.divider
        volumeSlider.thumbTintColor = colors.accent
    }
}
