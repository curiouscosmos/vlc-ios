/*****************************************************************************
 * DiscourseAudioMixerViewController.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * The Audio Mixer tab: the panel (switch, play/pause, loop, volume) plus the
 * ordered list of added local files, with reorder and delete. Tracks are added
 * from the local library's context menu, so the mixer never plays anything the
 * user did not choose.
 *****************************************************************************/

import UIKit

final class DiscourseAudioMixerViewController: UIViewController {
    private let mixer: DiscourseAudioMixer

    private let panel = DiscourseMixerPanelView()
    private let emptyStateView = DiscourseEmptyStateView(
        symbolName: "slider.horizontal.3",
        heading: NSLocalizedString("MIXER_EMPTY_TITLE",
                                   comment: "Empty state heading on the Audio Mixer tab"),
        message: NSLocalizedString("MIXER_EMPTY_MESSAGE",
                                   comment: "Empty state message on the Audio Mixer tab"),
        actionTitle: NSLocalizedString("MIXER_OPEN_LIBRARY",
                                       comment: "Action that opens the local library from the Audio Mixer"))
    private let hintLabel = UILabel()
    private let clearButton = UIButton(type: .system)

    private var tableView: UITableView!
    /// Width the current footerView was laid out for.
    private var footerWidth: CGFloat = 0

    init(mixer: DiscourseAudioMixer = .shared) {
        self.mixer = mixer
        super.init(nibName: nil, bundle: nil)
        title = NSLocalizedString("AUDIO_MIXER", comment: "Audio Mixer tab title")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = DiscourseColors.current.appBackground
        navigationItem.largeTitleDisplayMode = .always
        navigationItem.leftBarButtonItem = AppMenuBarButtonItem(presenter: self)
        navigationItem.rightBarButtonItem = editButtonItem

        setupTableView()
        setupPanel()
        setupFooter()

        emptyStateView.actionHandler = {
            NotificationCenter.default.post(name: .discourseShowLocalLibrary, object: nil)
        }

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateTheme),
                                               name: .VLCThemeDidChangeNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(mixerDidChange),
                                               name: .discourseMixerDidChange,
                                               object: nil)
        update()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        update()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sizeHeaderIfNeeded()
        if abs(tableView.bounds.width - footerWidth) > 0.5 {
            updateFooterView()
        }
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        if isViewLoaded {
            tableView.setEditing(editing, animated: animated)
        }
    }

    // MARK: - Setup

    private func setupTableView() {
        tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64
        tableView.allowsSelectionDuringEditing = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(DiscourseMixerTrackCell.self,
                           forCellReuseIdentifier: DiscourseMixerTrackCell.reuseIdentifier)

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupPanel() {
        panel.onToggleEnabled = { [weak self] enabled in
            self?.mixer.setEnabled(enabled)
        }
        panel.onTogglePlayback = { [weak self] in
            self?.mixer.togglePlayback()
        }
        panel.onToggleLoop = { [weak self] looping in
            self?.mixer.setLooping(looping)
        }
        panel.onVolumeChange = { [weak self] volume in
            self?.mixer.setVolume(volume)
        }
        tableView.tableHeaderView = panel
    }

    private func setupFooter() {
        hintLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        hintLabel.adjustsFontForContentSizeCategory = true
        hintLabel.numberOfLines = 0
        hintLabel.text = NSLocalizedString("MIXER_HINT",
                                           comment: "How to add tracks to the Audio Mixer")

        clearButton.setTitle(NSLocalizedString("MIXER_CLEAR",
                                               comment: "Remove every track from the Audio Mixer"),
                             for: .normal)
        clearButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        clearButton.titleLabel?.adjustsFontForContentSizeCategory = true
        clearButton.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)
    }

    // MARK: - Content

    @objc private func mixerDidChange() {
        update()
    }

    private func update() {
        let selected = mixer.selectedURL
        panel.configure(enabled: mixer.isEnabled,
                        isPlaying: mixer.isPlaying,
                        title: selected.map { DiscourseAudioMixer.displayTitle(for: $0) },
                        isLooping: mixer.isLooping,
                        volume: mixer.volume,
                        hasSelection: selected != nil)

        tableView.reloadData()
        navigationItem.rightBarButtonItem?.isEnabled = !mixer.items.isEmpty
        if isEditing, mixer.items.isEmpty {
            setEditing(false, animated: true)
        }

        sizeHeaderIfNeeded()
        updateFooterView()
        updateTheme()
    }

    private func sizeHeaderIfNeeded() {
        let width = tableView.bounds.width
        guard width > 0 else {
            return
        }
        let size = panel.systemLayoutSizeFitting(CGSize(width: width, height: 0),
                                                 withHorizontalFittingPriority: .required,
                                                 verticalFittingPriority: .fittingSizeLevel)
        if panel.frame.size != size {
            panel.frame = CGRect(origin: .zero, size: size)
            tableView.tableHeaderView = panel
        }
    }

    private func updateFooterView() {
        let width = tableView.bounds.width
        guard width > 0 else {
            return
        }
        footerWidth = width
        tableView.tableFooterView = makeFooterView(width: width)
    }

    /// A centred empty state when the mixer has no files, the hint plus a
    /// destructive **Clear all** otherwise.
    private func makeFooterView(width: CGFloat) -> UIView {
        let footer = UIView()

        if mixer.items.isEmpty {
            emptyStateView.translatesAutoresizingMaskIntoConstraints = false
            footer.addSubview(emptyStateView)
            NSLayoutConstraint.activate([
                emptyStateView.topAnchor.constraint(equalTo: footer.topAnchor, constant: 24),
                emptyStateView.bottomAnchor.constraint(equalTo: footer.bottomAnchor, constant: -24),
                emptyStateView.centerXAnchor.constraint(equalTo: footer.centerXAnchor),
                emptyStateView.leadingAnchor.constraint(greaterThanOrEqualTo: footer.leadingAnchor, constant: 24),
                emptyStateView.trailingAnchor.constraint(lessThanOrEqualTo: footer.trailingAnchor, constant: -24)
            ])
        } else {
            let stack = UIStackView(arrangedSubviews: [hintLabel, clearButton])
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.axis = .vertical
            stack.spacing = 12
            stack.alignment = .center
            footer.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: footer.topAnchor, constant: 16),
                stack.bottomAnchor.constraint(equalTo: footer.bottomAnchor, constant: -24),
                stack.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 24),
                stack.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -24)
            ])
        }

        let height = footer.systemLayoutSizeFitting(
            CGSize(width: width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel).height
        footer.frame = CGRect(x: 0, y: 0, width: width, height: height)
        return footer
    }

    // MARK: - Actions

    @objc private func clearTapped() {
        let alert = UIAlertController(
            title: NSLocalizedString("MIXER_CLEAR_CONFIRM",
                                     comment: "Confirmation before removing every Audio Mixer track"),
            message: nil,
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("BUTTON_CANCEL",
                                                               comment: "Cancel a destructive action"),
                                      style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("MIXER_CLEAR_ACTION",
                                                               comment: "Confirm removing every Audio Mixer track"),
                                      style: .destructive) { [weak self] _ in
            self?.mixer.clear()
        })
        present(alert, animated: true)
    }

    // MARK: - Theme

    @objc private func updateTheme() {
        let colors = DiscourseColors.current
        view.backgroundColor = colors.appBackground
        tableView.backgroundColor = .clear
        panel.updateTheme()
        emptyStateView.updateTheme()
        hintLabel.textColor = colors.secondaryText
        clearButton.tintColor = colors.likedHeart
        for cell in tableView.visibleCells {
            (cell as? DiscourseMixerTrackCell)?.updateTheme()
        }
    }
}

// MARK: - UITableViewDataSource

extension DiscourseAudioMixerViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return mixer.items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: DiscourseMixerTrackCell.reuseIdentifier,
                                                 for: indexPath)
        guard let trackCell = cell as? DiscourseMixerTrackCell else {
            return cell
        }
        let items = mixer.items
        guard items.indices.contains(indexPath.row) else {
            return trackCell
        }
        let url = items[indexPath.row]
        let selected = mixer.selectedURL
        trackCell.configure(title: DiscourseAudioMixer.displayTitle(for: url),
                            isSelected: url == selected,
                            isPlaying: mixer.isPlaying && url == selected)
        return trackCell
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    func tableView(_ tableView: UITableView,
                   commit editingStyle: UITableViewCell.EditingStyle,
                   forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else {
            return
        }
        mixer.remove(at: indexPath.row)
    }

    func tableView(_ tableView: UITableView,
                   moveRowAt sourceIndexPath: IndexPath,
                   to destinationIndexPath: IndexPath) {
        mixer.move(from: sourceIndexPath.row, to: destinationIndexPath.row)
    }
}

// MARK: - UITableViewDelegate

extension DiscourseAudioMixerViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !tableView.isEditing else {
            return
        }
        let items = mixer.items
        guard items.indices.contains(indexPath.row) else {
            return
        }
        mixer.select(items[indexPath.row])
        if !mixer.isPlaying {
            // Tapping a track is an explicit request to hear it.
            mixer.togglePlayback()
        }
    }
}
