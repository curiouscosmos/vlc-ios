/*****************************************************************************
 * DiscourseAudioMixerViewController.swift
 * Rajneesh Discourse
 *
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * The Audio Mixer tab: a wave-backed hero, the ordered track cards, an add
 * slot and the mixer panel (play/pause, loop and mixer-only volume). Tracks are
 * added explicitly through the system Files picker and copied into app-owned
 * storage, so they remain playable after relaunch. There is no Local Library
 * destination.
 *****************************************************************************/

import AVFoundation
import UIKit
import UniformTypeIdentifiers

final class DiscourseAudioMixerViewController: UIViewController {
    private let mixer: DiscourseAudioMixer
    private let fileImporter: DiscourseMixerFileImporter

    private let heroView = DiscourseMixerHeroView()
    private let addSlotView = DiscourseMixerAddSlotView()
    private let panel = DiscourseMixerPanelView()
    private let clearButton = UIButton(type: .system)

    private var tableView: UITableView!
    private var panelBottomConstraint: NSLayoutConstraint!
    private var appliedPanelInset: CGFloat = -1
    /// Width the current footer view was laid out for.
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

        view.backgroundColor = DiscourseColors.current.audioMixer.screenEnd
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
        setupHero()
        setupPanel()
        setupFooter()
        updateMiniPlayerInset()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateTheme),
                                               name: .VLCThemeDidChangeNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(mixerDidChange),
                                               name: .discourseMixerDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateFooterView),
                                               name: UIContentSizeCategory.didChangeNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateMiniPlayerInset),
                                               name: NSNotification.Name(rawValue: VLCPlayerDisplayControllerDisplayMiniPlayer),
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateMiniPlayerInset),
                                               name: NSNotification.Name(rawValue: VLCPlayerDisplayControllerHideMiniPlayer),
                                               object: nil)
        update()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        update()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sizeHeroIfNeeded()
        if abs(tableView.bounds.width - footerWidth) > 0.5 {
            updateFooterView()
        }
        refreshPanelLayout()
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
        tableView.estimatedRowHeight = 96
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

    private func setupHero() {
        addSlotView.onTap = { [weak self] in self?.presentAudioPicker() }
        tableView.tableHeaderView = heroView
    }

    private func setupPanel() {
        panel.onTogglePlayback = { [weak self] in
            self?.mixer.togglePlayback()
        }
        panel.onToggleEnabled = { [weak self] enabled in
            self?.mixer.setEnabled(enabled)
        }
        panel.onToggleLoop = { [weak self] looping in
            self?.mixer.setLooping(looping)
        }
        panel.onVolumeChange = { [weak self] volume in
            self?.mixer.setVolume(volume)
        }

        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)
        panelBottomConstraint = panel.bottomAnchor.constraint(equalTo: view.bottomAnchor,
                                                              constant: -12)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            panelBottomConstraint
        ])
        view.bringSubviewToFront(panel)
    }

    private func setupFooter() {
        clearButton.setTitle(NSLocalizedString("MIXER_CLEAR",
                                               comment: "Remove every track from the Audio Mixer"),
                             for: .normal)
        clearButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
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
        panel.configure(enabled: mixer.isEnabled,
                        isPlaying: mixer.isPlaying,
                        isLooping: mixer.isLooping,
                        volume: mixer.volume)

        tableView.reloadData()
        sizeHeroIfNeeded()
        updateFooterView()
        updateTheme()
        view.setNeedsLayout()
    }

    private func sizeHeroIfNeeded() {
        let width = tableView.bounds.width
        guard width > 0 else {
            return
        }
        let size = heroView.systemLayoutSizeFitting(CGSize(width: width, height: 0),
                                                    withHorizontalFittingPriority: .required,
                                                    verticalFittingPriority: .fittingSizeLevel)
        if heroView.frame.size != size {
            heroView.frame = CGRect(origin: .zero, size: size)
            tableView.tableHeaderView = heroView
        }
    }

    @objc private func updateFooterView() {
        let width = tableView.bounds.width
        guard width > 0 else {
            return
        }
        footerWidth = width

        let footer = UIView()
        let stack = UIStackView(arrangedSubviews: [addSlotView])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill
        if !mixer.items.isEmpty {
            stack.addArrangedSubview(clearButton)
        }
        footer.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: footer.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: footer.bottomAnchor, constant: -24)
        ])

        let height = footer.systemLayoutSizeFitting(
            CGSize(width: width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel).height
        footer.frame = CGRect(x: 0, y: 0, width: width, height: height)
        tableView.tableFooterView = footer
    }

    @objc private func updateMiniPlayerInset() {
        refreshPanelLayout()
    }

    /// The panel floats above the tab bar, so the table's last row must be able
    /// to scroll clear of it. The offset also moves the panel above the mini
    /// player while it is visible.
    private func refreshPanelLayout() {
        guard panelBottomConstraint != nil, view.bounds.height > 0 else {
            return
        }
        let visible = PlaybackService.sharedInstance().playerDisplayController.isMiniPlayerVisible
        let base = 12 + (visible ? CGFloat(AudioMiniPlayer.height) + 8 : 0)

        let tabBarTop: CGFloat
        if let tabBar = tabBarController?.tabBar, tabBar.window != nil {
            tabBarTop = tabBar.convert(tabBar.bounds, to: view).minY
        } else {
            tabBarTop = view.bounds.height - view.safeAreaInsets.bottom
        }
        guard tabBarTop > 0 else {
            return
        }
        let bottomOffset = view.bounds.height - tabBarTop + base
        if panelBottomConstraint.constant != -bottomOffset {
            panelBottomConstraint.constant = -bottomOffset
        }

        let width = max(0, view.bounds.width - 32)
        let size = panel.systemLayoutSizeFitting(CGSize(width: width, height: 0),
                                                 withHorizontalFittingPriority: .required,
                                                 verticalFittingPriority: .fittingSizeLevel)
        let panelTop = tabBarTop - base - size.height
        let inset = max(0, view.bounds.height - panelTop + 12)
        guard abs(inset - appliedPanelInset) > 0.5 else {
            return
        }
        appliedPanelInset = inset
        tableView.contentInset.bottom = inset
        tableView.verticalScrollIndicatorInsets.bottom = inset
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
        let colors = DiscourseColors.current.audioMixer
        view.backgroundColor = colors.screenEnd
        tableView.backgroundColor = .clear
        heroView.updateTheme()
        addSlotView.updateTheme()
        panel.updateTheme()
        clearButton.tintColor = colors.textSecondary
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
        trackCell.configure(url: url,
                            title: DiscourseAudioMixer.displayTitle(for: url),
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

// MARK: - Hero

private final class DiscourseMixerHeroView: UIView {
    private let backdropView = DiscourseMixerWaveView()
    private let equalizerView = DiscourseMixerEqualizerView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        backgroundColor = .clear
        backdropView.translatesAutoresizingMaskIntoConstraints = false
        equalizerView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = NSLocalizedString("MIXER_PANEL_TITLE",
                                            value: "Background Music Mixer",
                                            comment: "Mixer card heading")
        titleLabel.font = UIFont.preferredFont(forTextStyle: .title2).bolded
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = NSLocalizedString("MIXER_HERO_SUBTITLE",
                                               value: "Add background music and adjust the mix to your preference.",
                                               comment: "Audio Mixer hero subtitle")
        subtitleLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        addSubview(backdropView)
        addSubview(equalizerView)
        addSubview(titleLabel)
        addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            backdropView.topAnchor.constraint(equalTo: topAnchor),
            backdropView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdropView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdropView.bottomAnchor.constraint(equalTo: bottomAnchor),

            equalizerView.topAnchor.constraint(equalTo: topAnchor, constant: 44),
            equalizerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            equalizerView.widthAnchor.constraint(equalToConstant: 44),
            equalizerView.heightAnchor.constraint(equalToConstant: 36),

            titleLabel.topAnchor.constraint(equalTo: equalizerView.bottomAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 36),
            subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -36),
            subtitleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -28)
        ])

        updateTheme()
    }

    func updateTheme() {
        let colors = DiscourseColors.current.audioMixer
        titleLabel.textColor = colors.text
        subtitleLabel.textColor = colors.textSecondary
        equalizerView.updateTheme()
        backdropView.setNeedsDisplay()
    }
}

private final class DiscourseMixerEqualizerView: UIView {
    private let bars = [UIView(), UIView(), UIView(), UIView()]
    private let heights: [CGFloat] = [14, 24, 34, 20]

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        backgroundColor = .clear
        let stack = UIStackView(arrangedSubviews: bars)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 5
        stack.alignment = .center
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        for (index, bar) in bars.enumerated() {
            bar.layer.cornerRadius = 2
            bar.widthAnchor.constraint(equalToConstant: 4).isActive = true
            bar.heightAnchor.constraint(equalToConstant: heights[index]).isActive = true
        }
        updateTheme()
    }

    func updateTheme() {
        let colors = DiscourseColors.current
        for bar in bars {
            bar.backgroundColor = colors.audioMixer.accent
            bar.layer.shadowColor = colors.audioMixer.accent.cgColor
            bar.layer.shadowOpacity = colors.isDark ? 0.55 : 0.2
            bar.layer.shadowRadius = 8
            bar.layer.shadowOffset = .zero
        }
    }
}

private final class DiscourseMixerWaveView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }
        let colors = DiscourseColors.current.audioMixer
        drawGradient(in: context,
                     colors: [colors.screenStart, colors.screenEnd],
                     start: CGPoint(x: 0, y: 0),
                     end: CGPoint(x: 0, y: bounds.height))

        drawWave(in: context,
                 crest: 0.40,
                 amplitude: 0.10,
                 color: colors.bannerStart.withAlphaComponent(0.45),
                 phase: 0.10)
        drawWave(in: context,
                 crest: 0.54,
                 amplitude: 0.12,
                 color: colors.bannerStart.withAlphaComponent(0.68),
                 phase: 0.35)
        drawWave(in: context,
                 crest: 0.68,
                 amplitude: 0.12,
                 color: colors.bannerEnd.withAlphaComponent(0.68),
                 phase: 0.62)
        drawWave(in: context,
                 crest: 0.83,
                 amplitude: 0.08,
                 color: colors.accent.withAlphaComponent(0.28),
                 phase: 0.88)
    }

    private func drawGradient(in context: CGContext, colors: [UIColor], start: CGPoint, end: CGPoint) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors.map(\.cgColor) as CFArray,
                                        locations: [0, 1]) else {
            return
        }
        context.drawLinearGradient(gradient, start: start, end: end, options: [])
    }

    private func drawWave(in context: CGContext,
                          crest: CGFloat,
                          amplitude: CGFloat,
                          color: UIColor,
                          phase: CGFloat) {
        let width = bounds.width
        let height = bounds.height
        guard width > 0, height > 0 else {
            return
        }
        let path = UIBezierPath()
        let baseline = height * crest
        let start = CGPoint(x: 0, y: baseline)
        let end = CGPoint(x: width, y: baseline)
        let control1 = CGPoint(x: width * (0.18 + phase * 0.1),
                               y: baseline - height * amplitude)
        let control2 = CGPoint(x: width * (0.62 + phase * 0.1),
                               y: baseline + height * amplitude)
        path.move(to: start)
        path.addCurve(to: end, controlPoint1: control1, controlPoint2: control2)
        path.addLine(to: CGPoint(x: width, y: height))
        path.addLine(to: CGPoint(x: 0, y: height))
        path.close()

        context.saveGState()
        context.addPath(path.cgPath)
        context.clip()
        let top = color.withAlphaComponent(color.cgColor.alpha)
        let bottom = color.withAlphaComponent(0)
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: [top.cgColor, bottom.cgColor] as CFArray,
                                     locations: [0, 1]) {
            context.drawLinearGradient(gradient,
                                       start: CGPoint(x: 0, y: baseline - height * amplitude),
                                       end: CGPoint(x: 0, y: height),
                                       options: [])
        }
        context.restoreGState()

        // A faint crest line gives the waves the reference's glow.
        let crestPath = UIBezierPath()
        crestPath.move(to: start)
        crestPath.addCurve(to: end, controlPoint1: control1, controlPoint2: control2)
        context.addPath(crestPath.cgPath)
        context.setStrokeColor(color.withAlphaComponent(min(1, color.cgColor.alpha + 0.2)).cgColor)
        context.setLineWidth(1)
        context.strokePath()
    }
}

// MARK: - Add slot

private final class DiscourseMixerAddSlotView: UIControl {
    var onTap: (() -> Void)?

    private let borderLayer = CAShapeLayer()
    private let plusCircle = UIView()
    private let plusIcon = UIImageView()
    private let titleLabel = UILabel()
    private let formatsLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = NSLocalizedString("MIXER_ADD_FILE", comment: "Add an audio file to the Audio Mixer")
        accessibilityIdentifier = "discourseMixerAddSlot"
        addTarget(self, action: #selector(tapped), for: .touchUpInside)

        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.lineWidth = 1
        borderLayer.lineDashPattern = [6, 5]
        layer.addSublayer(borderLayer)

        plusCircle.translatesAutoresizingMaskIntoConstraints = false
        plusCircle.isUserInteractionEnabled = false
        plusCircle.layer.cornerRadius = 22
        plusCircle.layer.borderWidth = 1
        plusIcon.translatesAutoresizingMaskIntoConstraints = false
        plusIcon.image = UIImage(systemName: "plus",
                                 withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .regular))
        plusIcon.contentMode = .scaleAspectFit
        plusCircle.addSubview(plusIcon)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.isUserInteractionEnabled = false
        titleLabel.text = NSLocalizedString("MIXER_ADD_SLOT_TITLE",
                                            value: "Tap + to add an audio file",
                                            comment: "Audio Mixer add slot title")
        titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        formatsLabel.translatesAutoresizingMaskIntoConstraints = false
        formatsLabel.isUserInteractionEnabled = false
        formatsLabel.text = NSLocalizedString("MIXER_ADD_SLOT_FORMATS",
                                              value: "Supported formats: MP3, WAV, M4A, AAC",
                                              comment: "Audio Mixer supported formats")
        formatsLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        formatsLabel.adjustsFontForContentSizeCategory = true
        formatsLabel.textAlignment = .center
        formatsLabel.numberOfLines = 0

        addSubview(plusCircle)
        addSubview(titleLabel)
        addSubview(formatsLabel)
        NSLayoutConstraint.activate([
            plusCircle.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            plusCircle.centerXAnchor.constraint(equalTo: centerXAnchor),
            plusCircle.widthAnchor.constraint(equalToConstant: 40),
            plusCircle.heightAnchor.constraint(equalToConstant: 40),

            plusIcon.centerXAnchor.constraint(equalTo: plusCircle.centerXAnchor),
            plusIcon.centerYAnchor.constraint(equalTo: plusCircle.centerYAnchor),
            plusIcon.widthAnchor.constraint(equalToConstant: 20),
            plusIcon.heightAnchor.constraint(equalToConstant: 20),

            titleLabel.topAnchor.constraint(equalTo: plusCircle.bottomAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            formatsLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            formatsLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            formatsLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            formatsLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14)
        ])
        updateTheme()
    }

    @objc private func tapped() {
        onTap?()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        borderLayer.frame = bounds
        borderLayer.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                        cornerRadius: 16).cgPath
    }

    func updateTheme() {
        let colors = DiscourseColors.current.audioMixer
        backgroundColor = colors.card.withAlphaComponent(0.35)
        borderLayer.strokeColor = colors.separator.cgColor
        plusCircle.layer.borderColor = colors.accent.withAlphaComponent(0.65).cgColor
        plusIcon.tintColor = colors.accent
        titleLabel.textColor = colors.text
        formatsLabel.textColor = colors.textSecondary
    }
}
