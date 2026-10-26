/*****************************************************************************
 * DiscourseScreenViewController.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * Base class of the fork's root screens. It provides the dark-first background,
 * the Settings menu bar button every root screen offers, the theme refresh and a
 * centred empty state. Later phases replace the empty state with real content
 * and hide it, but keep the chrome.
 *****************************************************************************/

import UIKit

class DiscourseScreenViewController: UIViewController {
    /// The empty state shown while the screen has nothing to display.
    let emptyStateView: DiscourseEmptyStateView

    init(title: String,
         symbolName: String,
         heading: String,
         message: String,
         actionTitle: String? = nil) {
        emptyStateView = DiscourseEmptyStateView(symbolName: symbolName,
                                                 heading: heading,
                                                 message: message,
                                                 actionTitle: actionTitle)
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = DiscourseColors.current.appBackground
        navigationItem.largeTitleDisplayMode = .always
        navigationItem.leftBarButtonItem = AppMenuBarButtonItem(presenter: self)

        addEmptyState()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateTheme),
                                               name: .VLCThemeDidChangeNotification,
                                               object: nil)
    }

    private func addEmptyState() {
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyStateView)

        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            emptyStateView.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: safeArea.centerYAnchor),
            emptyStateView.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor, constant: 24),
            emptyStateView.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor, constant: -24),
            emptyStateView.widthAnchor.constraint(lessThanOrEqualToConstant: 480)
        ])
    }

    @objc func updateTheme() {
        view.backgroundColor = DiscourseColors.current.appBackground
        emptyStateView.updateTheme()
    }
}
