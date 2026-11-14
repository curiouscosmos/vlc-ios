/*****************************************************************************
 * DiscourseUpdateViewController.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 *****************************************************************************/

import UIKit

/// A separate alert-level window keeps forced updates above presented players and sheets.
final class DiscourseUpdateViewController: UIViewController {
    private let forceUpdate: Bool
    private let update: () -> Void
    private let skip: () -> Void
    private let card = UIScrollView()
    private let stack = UIStackView()

    init(forceUpdate: Bool, update: @escaping () -> Void, skip: @escaping () -> Void) {
        self.forceUpdate = forceUpdate
        self.update = update
        self.skip = skip
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        view.accessibilityViewIsModal = true
        card.layer.cornerRadius = 20
        view.addSubview(card)
        stack.axis = .vertical
        stack.spacing = 16
        card.addSubview(stack)
        let content = DiscourseEmptyStateView(
            symbolName: "arrow.down.app",
            heading: NSLocalizedString("DISCOURSE_UPDATE_TITLE", comment: "App update dialog title"),
            message: forceUpdate
                ? NSLocalizedString("DISCOURSE_UPDATE_REQUIRED", comment: "Please update Rajneesh Discourse to continue using the app.")
                : NSLocalizedString("DISCOURSE_UPDATE_OPTIONAL", comment: "A newer version of Rajneesh Discourse is available. Update from the App Store."),
            actionTitle: NSLocalizedString("DISCOURSE_UPDATE_ACTION", comment: "Open the App Store"))
        content.actionHandler = update
        stack.addArrangedSubview(content)
        if !forceUpdate {
            let button = UIButton(type: .system)
            let title = NSLocalizedString("DISCOURSE_UPDATE_SKIP", comment: "Skip this app update")
            button.setTitle(title, for: .normal)
            button.accessibilityLabel = title
            button.titleLabel?.font = .preferredFont(forTextStyle: .body)
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            button.addAction(UIAction { [weak self] _ in self?.skip() }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(updateTheme),
                                               name: .VLCThemeDidChangeNotification, object: nil)
        updateTheme()
    }

    @objc private func updateTheme() {
        card.backgroundColor = DiscourseColors.current.appBackground
        view.tintColor = DiscourseColors.current.accent
        (stack.arrangedSubviews.first as? DiscourseEmptyStateView)?.updateTheme()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let safe = view.safeAreaLayoutGuide.layoutFrame.insetBy(dx: 20, dy: 20)
        let width = min(400, safe.width)
        let size = stack.systemLayoutSizeFitting(CGSize(width: width - 48, height: 0),
                                                withHorizontalFittingPriority: .required,
                                                verticalFittingPriority: .fittingSizeLevel)
        let height = min(safe.height, size.height + 48)
        card.frame = CGRect(x: safe.midX - width / 2, y: safe.midY - height / 2, width: width, height: height)
        stack.frame = CGRect(x: 24, y: 24, width: width - 48, height: size.height)
        card.contentSize = CGSize(width: width, height: size.height + 48)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        view.setNeedsLayout()
    }

    override func accessibilityPerformEscape() -> Bool {
        if !forceUpdate { skip() }
        return true
    }
}
