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
 * explicitly through the system Files picker and copied into app-owned storage,
 * so they remain playable after relaunch. There is no Local Library destination.
 *****************************************************************************/

import UIKit
import UniformTypeIdentifiers

final class DiscourseAudioMixerViewController: UIViewController {
    private let mixer: DiscourseAudioMixer
    private let fileImporter: DiscourseMixerFileImporter

    private let panel = DiscourseMixerPanelView()
    private let emptyStateView = DiscourseEmptyStateView(
        symbolName: "slider.horizontal.3",
        heading: NSLocalizedString("MIXER_EMPTY_TITLE",
                                   comment: "Empty state heading on the Audio Mixer tab"),
        message: NSLocalizedString("MIXER_EMPTY_MESSAGE",
                                   comment: "Empty state message on the Audio Mixer tab"),
        actionTitle: NSLocalizedString("MIXER_ADD_FILE",
                                       comment: "Add an audio file to the Audio Mixer"))
    private let hintLabel = UILabel()
    private let clearButton = UIButton(type: .system)

    private var tableView: UITableView!
    /// Width the current footerView was laid out for.
    private var footerWidth: CGFloat = 0

    init(mixer: DiscourseAudioMixer = .shared,
         fileImporter: DiscourseMixerFileImporter = DiscourseMixerFileImporter()) {
        self.mixer = mixer
        self.fileImporter = fileImporter
        super.init(nibName: nil, bundle: nil)
        // The tab carries the name; the screen shows its content without a
        // navigation title.
        title = nil
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = DiscourseColors.current.appBackground
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.leftBarButtonItem = AppMenuBarButtonItem(presenter: self)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            style: .plain,
            target: self,
            action: #selector(presentAudioPicker))
        navigationItem.rightBarButtonItem?.accessibilityLabel = NSLocalizedString(
            "MIXER_ADD_FILE", comment: "Add an audio file to the Audio Mixer")
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "discourseMixerAddAudio"

        setupTableView()
        setupPanel()
        setupFooter()

        emptyStateView.actionHandler = { [weak self] in
            self?.presentAudioPicker()
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

    // MARK: - Setup

    @objc private func presentAudioPicker() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.audio])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    private func setupTableView() {
        tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64
        tableView.dataSource = self
        tableView.delegate = self
        // No Edit button: rows reorder by long-press drag and are removed by
        // swiping.
        tableView.dragInteractionEnabled = true
        tableView.dragDelegate = self
        tableView.dropDelegate = self
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
        panel.onLayoutChange = { [weak self] in self?.sizeHeaderIfNeeded() }
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

    /// A drag reorder updates the table with its own animation, so the mixer's
    /// change notification must not reload it in the middle of the drop.
    private var isApplyingReorder = false

    @objc private func mixerDidChange() {
        guard !isApplyingReorder else { return }
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
            panel.onLayoutChange = { [weak self] in self?.sizeHeaderIfNeeded() }
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

    private func showImportError() {
        let alert = UIAlertController(
            title: NSLocalizedString("MIXER_IMPORT_FAILED_TITLE",
                                     comment: "Could not add an audio file to the Audio Mixer"),
            message: NSLocalizedString("MIXER_IMPORT_FAILED_MESSAGE",
                                       comment: "The selected audio file could not be copied"),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("BUTTON_OK", comment: ""),
                                      style: .default))
        present(alert, animated: true)
    }

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

    func tableView(_ tableView: UITableView,
                   commit editingStyle: UITableViewCell.EditingStyle,
                   forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else {
            return
        }
        mixer.remove(at: indexPath.row)
    }
}

// MARK: - UITableViewDragDelegate

extension DiscourseAudioMixerViewController: UITableViewDragDelegate {
    func tableView(_ tableView: UITableView,
                   itemsForBeginning session: UIDragSession,
                   at indexPath: IndexPath) -> [UIDragItem] {
        let items = mixer.items
        guard items.indices.contains(indexPath.row) else {
            return []
        }
        let url = items[indexPath.row]
        let itemProvider = NSItemProvider(object: url.absoluteString as NSString)
        let dragItem = UIDragItem(itemProvider: itemProvider)
        dragItem.localObject = url
        return [dragItem]
    }
}

// MARK: - UITableViewDropDelegate

extension DiscourseAudioMixerViewController: UITableViewDropDelegate {
    func tableView(_ tableView: UITableView, canHandle session: UIDropSession) -> Bool {
        // Reordering only; the mixer never accepts files dragged in from outside.
        return session.localDragSession != nil
    }

    func tableView(_ tableView: UITableView,
                   dropSessionDidUpdate session: UIDropSession,
                   withDestinationIndexPath destinationIndexPath: IndexPath?) -> UITableViewDropProposal {
        return UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
        guard let item = coordinator.items.first,
              let sourceIndexPath = item.sourceIndexPath,
              let destinationIndexPath = coordinator.destinationIndexPath,
              sourceIndexPath.row != destinationIndexPath.row else {
            return
        }

        isApplyingReorder = true
        mixer.move(from: sourceIndexPath.row, to: destinationIndexPath.row)
        isApplyingReorder = false

        tableView.performBatchUpdates {
            tableView.moveRow(at: sourceIndexPath, to: destinationIndexPath)
        }
        coordinator.drop(item.dragItem, toRowAt: destinationIndexPath)
    }
}

// MARK: - UITableViewDelegate

extension DiscourseAudioMixerViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
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

// MARK: - UIDocumentPickerDelegate

extension DiscourseAudioMixerViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let sourceURL = urls.first else {
            return
        }
        do {
            let importedURL = try fileImporter.import(sourceURL)
            // Membership, persistence and the row refresh already live here.
            mixer.add(importedURL)
        } catch {
            showImportError()
        }
    }
}
