/*****************************************************************************
 * DiscourseEmptyStateView.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * The shared "nothing to show" block of the fork screens: a symbol, a heading,
 * an explanation and an optional action. It uses the DiscourseColors tokens so
 * it follows the existing light/dark switch, and it scales with Dynamic Type.
 *****************************************************************************/

import UIKit

final class DiscourseEmptyStateView: UIView {
    private let symbolView = UIImageView()
    private let headingLabel = UILabel()
    private let messageLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private let stackView = UIStackView()
    private let actionTitle: String?

    /// Invoked when the optional action button is tapped.
    var actionHandler: (() -> Void)?

    init(symbolName: String, heading: String, message: String, actionTitle: String? = nil) {
        self.actionTitle = actionTitle
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setupSymbol(symbolName)
        setupLabels(heading: heading, message: message)
        setupStack()
        setupAction()
        updateTheme()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupSymbol(_ symbolName: String) {
        let configuration = UIImage.SymbolConfiguration(pointSize: 44, weight: .regular)
        symbolView.image = UIImage(systemName: symbolName, withConfiguration: configuration)
        symbolView.contentMode = .scaleAspectFit
        symbolView.isAccessibilityElement = false
        symbolView.setContentHuggingPriority(.required, for: .vertical)
    }

    private func setupLabels(heading: String, message: String) {
        headingLabel.text = heading
        headingLabel.font = UIFont.preferredFont(forTextStyle: .title3)
        headingLabel.adjustsFontForContentSizeCategory = true
        headingLabel.numberOfLines = 0
        headingLabel.textAlignment = .center
        headingLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        headingLabel.accessibilityTraits = .header

        messageLabel.text = message
        messageLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    private func setupStack() {
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false

        stackView.addArrangedSubview(symbolView)
        stackView.setCustomSpacing(20, after: symbolView)
        stackView.addArrangedSubview(headingLabel)
        stackView.addArrangedSubview(messageLabel)

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func setupAction() {
        guard let actionTitle else {
            return
        }

        var configuration = UIButton.Configuration.filled()
        configuration.title = actionTitle
        configuration.cornerStyle = .medium
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.preferredFont(forTextStyle: .headline)
            return outgoing
        }
        actionButton.configuration = configuration
        actionButton.addTarget(self, action: #selector(handleAction), for: .touchUpInside)
        actionButton.accessibilityLabel = actionTitle
        stackView.setCustomSpacing(24, after: messageLabel)
        stackView.addArrangedSubview(actionButton)
    }

    // MARK: - Theme

    @objc func updateTheme() {
        let colors = DiscourseColors.current
        symbolView.tintColor = colors.accent
        headingLabel.textColor = colors.primaryText
        messageLabel.textColor = colors.secondaryText

        guard actionTitle != nil, var configuration = actionButton.configuration else {
            return
        }
        configuration.baseBackgroundColor = colors.accent
        configuration.baseForegroundColor = .white
        actionButton.configuration = configuration
    }

    // MARK: - Actions

    @objc private func handleAction() {
        actionHandler?()
    }
}
