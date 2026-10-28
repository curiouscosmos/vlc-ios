/*****************************************************************************
 * DiscourseSegmentControl.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * The Discourses tab's Discourse | Local switch. UIKit's `UISegmentedControl`
 * cannot paint its selected segment with the brand primary on iOS 26 (the
 * Liquid Glass control ignores `selectedSegmentTintColor`), so this small
 * control draws the selected tab itself. It keeps the segmented-control
 * accessibility model: each option is a button with the selected trait.
 *****************************************************************************/

import UIKit

final class DiscourseSegmentControl: UIView {
    private let stackView = UIStackView()
    private var items: [SegmentItem] = []

    private(set) var selectedSegmentIndex = 0

    /// Called when the user selects another segment. Programmatic selection
    /// (`setSelectedSegmentIndex(_:)`) does not notify.
    var onSelectionChanged: ((Int) -> Void)?

    init(items: [String]) {
        super.init(frame: .zero)
        setup(items: items)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Selection

    func setSelectedSegmentIndex(_ index: Int) {
        guard items.indices.contains(index) else {
            return
        }
        selectedSegmentIndex = index
        updateSelection()
    }

    // MARK: - Theme

    func applyTheme() {
        let colors = DiscourseColors.current
        backgroundColor = colors.surfaceStart
        layer.borderColor = colors.border.cgColor
        updateSelection()
    }

    // MARK: - Setup

    private func setup(items titles: [String]) {
        isAccessibilityElement = false
        accessibilityIdentifier = "discoursesSegment"
        layer.borderWidth = 1
        clipsToBounds = true

        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = 2
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3)
        ])

        for (index, title) in titles.enumerated() {
            let item = SegmentItem(title: title, index: index)
            item.addTarget(self, action: #selector(segmentTapped(_:)), for: .touchUpInside)
            self.items.append(item)
            stackView.addArrangedSubview(item)
        }

        applyTheme()
        setSelectedSegmentIndex(0)
    }

    @objc private func segmentTapped(_ sender: SegmentItem) {
        guard items.indices.contains(sender.index),
              sender.index != selectedSegmentIndex else {
            return
        }
        selectedSegmentIndex = sender.index
        updateSelection()
        onSelectionChanged?(sender.index)
    }

    private func updateSelection() {
        for (index, item) in items.enumerated() {
            item.applyTheme(isSelected: index == selectedSegmentIndex)
        }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        let itemRadius = max(0, (bounds.height - 6) / 2)
        for item in items {
            item.layer.cornerRadius = itemRadius
        }
    }

    override var intrinsicContentSize: CGSize {
        let size = stackView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        return CGSize(width: size.width + 6, height: size.height + 6)
    }
}

/// One option: a label with the button trait and the selected state.
private final class SegmentItem: UIControl {
    let index: Int

    private let label = UILabel()

    init(title: String, index: Int) {
        self.index = index
        super.init(frame: .zero)

        clipsToBounds = true
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityIdentifier = "discoursesSegmentOption\(index)"
        accessibilityTraits = [.button]

        label.text = title
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.isUserInteractionEnabled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyTheme(isSelected: Bool) {
        let colors = DiscourseColors.current
        self.isSelected = isSelected
        backgroundColor = isSelected ? colors.accent : .clear
        label.textColor = isSelected ? .white : colors.primaryText
        accessibilityTraits = isSelected ? [.button, .selected] : [.button]
    }

    override func accessibilityActivate() -> Bool {
        sendActions(for: .touchUpInside)
        return true
    }
}
