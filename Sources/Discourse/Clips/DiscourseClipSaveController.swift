/*
 * Copyright (c) 2026 Sandalbar Enterprises, Inc.
 * Part of Rajneesh Discourse. GPLv2 or later; see COPYING.
 */
import UIKit
import PhotosUI
import UniformTypeIdentifiers

final class DiscourseClipSaveController: UITableViewController, UIDocumentPickerDelegate, PHPickerViewControllerDelegate {
    private let track: DiscourseAudio
    private let range: DiscourseClipRange
    private let exporter = DiscourseClipExporter()
    private var timer: Timer?
    private var busy = false
    private var exporting = false
    private var operation = UUID()
    private var status: String?
    private var progressController: DiscourseClipProgressController?
    private var exportCC = false
    private var requestedCC = false
    private var fadeIn = true
    private var fadeOut = true
    private var visual: URL?
    private var visualDirectory: URL?
    private var captionTask: Task<Void, Never>?
    private var visualProgress: Progress?
    private var request: DiscourseClipExportRequest?

    init(track: DiscourseAudio, range: DiscourseClipRange) {
        self.track = track
        self.range = range
        super.init(style: .insetGrouped)
        title = NSLocalizedString("CLIP_EXPORT_TITLE", comment: "")
        navigationItem.largeTitleDisplayMode = .never
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { visualProgress?.cancel(); captionTask?.cancel(); if let visualDirectory { try? FileManager.default.removeItem(at: visualDirectory) }; timer?.invalidate(); NotificationCenter.default.removeObserver(self); exporter.cancel(); exporter.clean() }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = DiscourseColors.current.surfaceStart
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 86
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "xmark"), style: .plain, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem?.accessibilityLabel = NSLocalizedString("BUTTON_CLOSE", comment: "")
        for name in [Notification.Name(rawValue: VLCPlaybackServiceNoiseReductionDidChange), .discourseMixerDidChange,
                     .VLCThemeDidChangeNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(refreshSettings), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(background), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }
    @objc private func refreshSettings() {
        tableView.backgroundColor = DiscourseColors.current.surfaceStart
        tableView.reloadData()
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 4 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        [1, 3, 2, 3][section]
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = DiscourseColors.current.surfaceEnd
        cell.textLabel?.textColor = DiscourseColors.current.primaryText
        cell.detailTextLabel?.textColor = DiscourseColors.current.primaryText.withAlphaComponent(0.65)
        cell.selectionStyle = .none
        let row = indexPath.row
        let service = PlaybackService.sharedInstance()
        let mixer = DiscourseAudioMixer.shared
        if indexPath.section == 0 {
            let artwork = VLCNetworkImageView()
            artwork.translatesAutoresizingMaskIntoConstraints = false
            artwork.contentMode = .scaleAspectFill
            artwork.clipsToBounds = true
            artwork.layer.cornerRadius = 12
            if let url = track.thumbnailURL { artwork.setImageWith(url, maxPixelSize: 400) }
            else {
                artwork.image = UIImage(systemName: "waveform")
                artwork.contentMode = .scaleAspectFit
                artwork.tintColor = DiscourseColors.current.accent
            }
            let title = UILabel()
            title.text = track.title
            title.font = .preferredFont(forTextStyle: .title2, compatibleWith: traitCollection)
            title.textColor = DiscourseColors.current.primaryText
            title.adjustsFontForContentSizeCategory = true
            title.numberOfLines = 0
            let time = UILabel()
            time.text = DiscourseClipRange.time(range.start) + " – " + DiscourseClipRange.time(range.end)
            time.font = .preferredFont(forTextStyle: .body, compatibleWith: traitCollection)
            time.textColor = DiscourseColors.current.primaryText
            time.adjustsFontForContentSizeCategory = true
            time.numberOfLines = 0
            let stack = UIStackView(arrangedSubviews: [artwork, title, time])
            stack.axis = .vertical; stack.spacing = 12; stack.alignment = .center
            stack.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
                stack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 16),
                stack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -16),
                artwork.widthAnchor.constraint(equalToConstant: 128), artwork.heightAnchor.constraint(equalTo: artwork.widthAnchor)
            ])
        } else if indexPath.section == 1 || indexPath.section == 2 {
            let settings = indexPath.section == 1
            let titles = settings
                ? [NSLocalizedString("CLIP_NOISE", comment: ""), NSLocalizedString("CLIP_MUSIC", comment: ""),
                   NSLocalizedString("CLIP_EXPORT_CC", comment: "")]
                : [NSLocalizedString("CLIP_FADE_IN", comment: ""), NSLocalizedString("CLIP_FADE_OUT", comment: "")]
            cell.textLabel?.text = titles[row]
            let toggle = UISwitch()
            toggle.onTintColor = DiscourseColors.current.accent
            toggle.tag = settings ? row : row + 3
            toggle.isOn = settings ? [service.noiseReductionEnabled, mixer.isEnabled, exportCC][row] : [fadeIn, fadeOut][row]
            let available = !settings || (row == 0 ? service.noiseReductionAvailable : row == 1 ? mixer.selectedURL != nil : track.captionURL != nil)
            toggle.isEnabled = !busy && available
            if !available {
                cell.detailTextLabel?.text = row == 1 ? NSLocalizedString("CLIP_ADD_MUSIC", comment: "") : NSLocalizedString("CLIP_UNAVAILABLE", comment: "")
            }
            toggle.accessibilityLabel = cell.textLabel?.text
            toggle.accessibilityHint = cell.detailTextLabel?.text
            toggle.accessibilityIdentifier = "clipSetting\(toggle.tag)"
            toggle.addTarget(self, action: #selector(settingChanged(_:)), for: .valueChanged)
            cell.accessoryView = toggle
        } else {
            var configuration = UIButton.Configuration.filled()
            configuration.title = [NSLocalizedString("CLIP_SHARE_LINK", comment: ""),
                NSLocalizedString("CLIP_DOWNLOAD_AUDIO", comment: ""), NSLocalizedString("CLIP_CREATE_VIDEO", comment: "")][row]
            configuration.subtitle = row == 0 ? NSLocalizedString("CLIP_SHARE_DESCRIPTION", comment: "")
                : status ?? (row == 2 ? NSLocalizedString("CLIP_SELECT_VISUAL", comment: "") : nil)
            configuration.image = UIImage(systemName: ["square.and.arrow.up", "arrow.down.to.line", "video"][row])
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 24)
            configuration.imagePadding = 12
            configuration.titleAlignment = .leading
            configuration.titleLineBreakMode = .byWordWrapping
            configuration.subtitleLineBreakMode = .byWordWrapping
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 18, leading: 16, bottom: 18, trailing: 16)
            configuration.baseBackgroundColor = DiscourseColors.current.accent
            configuration.baseForegroundColor = .white
            let button = UIButton(configuration: configuration)
            button.configurationUpdateHandler = { button in
                let traits = button.traitCollection
                button.configuration?.imagePlacement = traits.preferredContentSizeCategory.isAccessibilityCategory ? .top : .leading
                button.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                    var attributes = attributes
                    attributes.font = UIFont.preferredFont(forTextStyle: .headline, compatibleWith: traits)
                    return attributes
                }
            }
            button.tag = row
            button.isEnabled = !busy
            button.accessibilityLabel = configuration.title
            button.accessibilityHint = configuration.subtitle
            button.translatesAutoresizingMaskIntoConstraints = false
            button.addTarget(self, action: #selector(exportAction(_:)), for: .touchUpInside)
            cell.backgroundColor = .clear
            cell.separatorInset = UIEdgeInsets(top: 0, left: tableView.bounds.width, bottom: 0, right: 0)
            cell.contentView.addSubview(button)
            NSLayoutConstraint.activate([
                button.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
                button.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor),
                button.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 6),
                button.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -6),
                button.heightAnchor.constraint(greaterThanOrEqualToConstant: 64)
            ])
        }
        cell.textLabel?.font = .preferredFont(forTextStyle: .headline, compatibleWith: traitCollection)
        cell.detailTextLabel?.font = .preferredFont(forTextStyle: .subheadline, compatibleWith: traitCollection)
        for label in [cell.textLabel, cell.detailTextLabel] {
            label?.adjustsFontForContentSizeCategory = true
            label?.numberOfLines = 0
        }
        cell.contentView.directionalLayoutMargins.top = 18
        cell.contentView.directionalLayoutMargins.bottom = 18
        return cell
    }
    @objc private func settingChanged(_ sender: UISwitch) {
        guard !busy else { return }
        switch sender.tag {
        case 0: _ = PlaybackService.sharedInstance().setNoiseReduction(enabled: sender.isOn)
        case 1: DiscourseAudioMixer.shared.setEnabled(sender.isOn)
        case 2: exportCC = sender.isOn
        case 3: fadeIn = sender.isOn
        case 4: fadeOut = sender.isOn
        default: break
        }
        refreshSettings()
    }
    @objc private func exportAction(_ sender: UIButton) {
        tableView(tableView, didSelectRowAt: IndexPath(row: sender.tag, section: 3))
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !busy, indexPath.section == 3 else { return }
        if indexPath.row == 0 {
            guard let url = DiscourseDeepLink.clipURL(discourseID: track.discourseID, audioID: track.id,
                                                       start: range.start, end: range.end) else { return }
            let activity = UIActivityViewController(activityItems: [track.title, url], applicationActivities: nil)
            activity.popoverPresentationController?.sourceView = tableView
            activity.popoverPresentationController?.sourceRect = tableView.rectForRow(at: indexPath)
            present(activity, animated: true)
        } else if indexPath.row == 2 {
            snapshotSettings()
            var configuration = PHPickerConfiguration()
            configuration.selectionLimit = 1
            configuration.filter = .any(of: [.images, .videos])
            let picker = PHPickerViewController(configuration: configuration)
            picker.delegate = self
            present(picker, animated: true)
        } else {
            clearVisual()
            snapshotSettings()
            download()
        }
    }
    private func snapshotSettings() {
        requestedCC = exportCC
        let mixer = DiscourseAudioMixer.shared
        request = DiscourseClipExportRequest(source: URL(fileURLWithPath: "/"), sourceExtension: track.audioURL?.pathExtension,
            title: track.title, range: range, noise: PlaybackService.sharedInstance().noiseReductionEnabled,
            music: mixer.selectedURL, musicEnabled: mixer.isEnabled && mixer.selectedURL != nil,
            musicVolume: Float(mixer.volume) / 100, musicLoops: mixer.isLooping, fadeIn: fadeIn, fadeOut: fadeOut)
    }
    private func download() {
        status = nil
        busy = true
        exporting = false
        isModalInPresentation = true
        operation = UUID()
        request?.visual = visual
        showProgress(isVideo: visual != nil)
        tableView.reloadData()
        if DiscourseDownloadStore.shared.localURL(for: track.id) == nil {
            guard track.audioURL != nil else { fail(); return }
            DiscourseDownloadManager.shared.download(track)
        }
        poll()
        if busy && !exporting && timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.poll() }
        }
    }
    private func poll() {
        guard busy && !exporting else { return }
        if let source = DiscourseDownloadStore.shared.localURL(for: track.id) {
            timer?.invalidate(); timer = nil
            exporting = true
            progressController?.update(progress: 0)
            let token = operation
            guard let snapshot = request else { fail(); return }
            captionTask = Task { [weak self] in
                guard let self else { return }
                do {
                    var captions: [DiscourseCaption]?
                    if self.requestedCC {
                        guard let url = self.track.captionURL else { throw DiscourseClipExporter.error("CLIP_CC_FAILED") }
                        do { captions = try await DiscourseCaptionLoader().load(url: url) }
                        catch { throw DiscourseClipExporter.error("CLIP_CC_FAILED") }
                        guard !(DiscourseCaptions.srt(captions ?? [], start: self.range.start, end: self.range.end)).isEmpty else {
                            throw DiscourseClipExporter.error("CLIP_CC_FAILED")
                        }
                    }
                    try Task.checkCancellation()
                    guard self.operation == token else { return }
                    let request = DiscourseClipExportRequest(source: source, sourceExtension: snapshot.sourceExtension,
                        title: snapshot.title, range: snapshot.range, visual: snapshot.visual, noise: snapshot.noise,
                        music: snapshot.music, musicEnabled: snapshot.musicEnabled, musicVolume: snapshot.musicVolume,
                        musicLoops: snapshot.musicLoops, captions: captions, fadeIn: snapshot.fadeIn, fadeOut: snapshot.fadeOut)
                    self.exporter.export(request, progress: { [weak self] fraction in
                        guard let self, self.operation == token else { return }
                        self.progressController?.update(progress: fraction)
                    }) { [weak self] result in
                        guard let self, self.operation == token else { return }
                        // Keep options disabled until Files relinquishes the temporary output.
                        switch result {
                        case .success(let urls):
                            let picker = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
                            picker.delegate = self
                            self.closeProgress { [weak self] in
                                guard let self, self.operation == token, self.busy else { return }
                                self.present(picker, animated: true)
                            }
                        case .failure(let error): self.fail(error)
                        }
                    }
                } catch {
                    guard self.operation == token else { return }
                    self.fail(error)
                }
            }
        } else {
            switch DiscourseDownloadManager.shared.state(for: track.id) {
            case .failed, .missing: fail()
            case .downloading(let progress):
                progressController?.update(progress: progress,
                    status: String(format: NSLocalizedString("CLIP_DOWNLOADING", comment: ""), Int(progress * 100)))
            case .downloaded: fail()
            }
        }
    }
    private func fail(_ error: Error? = nil) {
        timer?.invalidate(); timer = nil
        busy = false
        isModalInPresentation = false
        closeProgress()
        status = error?.localizedDescription ?? NSLocalizedString("CLIP_FAILED", comment: "")
        tableView.reloadData()
    }
    private func showProgress(isVideo: Bool) {
        guard progressController == nil else { return }
        let progress = DiscourseClipProgressController(isVideo: isVideo)
        progress.onCancel = { [weak self] in self?.cancelExport() }
        progressController = progress
        present(progress, animated: false)
    }
    private func closeProgress(completion: (() -> Void)? = nil) {
        guard let progress = progressController else { completion?(); return }
        progressController = nil
        progress.dismiss(animated: true, completion: completion)
    }
    private func cancelExport() {
        operation = UUID()
        visualProgress?.cancel(); captionTask?.cancel(); timer?.invalidate(); timer = nil
        exporter.cancel()
        closeProgress()
        finished()
    }
    @objc private func background() {
        guard busy, !(presentedViewController is UIDocumentPickerViewController) else { return }
        operation = UUID(); visualProgress?.cancel(); captionTask?.cancel(); exporter.cancel(); exporter.clean(); fail()
    }
    @objc private func cancel() {
        operation = UUID(); visualProgress?.cancel(); captionTask?.cancel(); timer?.invalidate(); timer = nil; exporter.cancel()
        dismiss(animated: true)
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finished() }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { finished() }
    private func finished() {
        busy = false; exporting = false; isModalInPresentation = false
        exporter.clean(); clearVisual(); status = nil; tableView.reloadData()
    }
    private func clearVisual() {
        if let visualDirectory { try? FileManager.default.removeItem(at: visualDirectory) }
        visualDirectory = nil; visual = nil
    }
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        guard let provider = results.first?.itemProvider else { picker.dismiss(animated: true); return }
        picker.dismiss(animated: true) { [weak self] in self?.loadVisual(provider) }
    }
    private func loadVisual(_ provider: NSItemProvider) {
        showProgress(isVideo: true)
        busy = true; isModalInPresentation = true; operation = UUID()
        let token = operation
        tableView.reloadData()
        let type = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) ? UTType.movie.identifier : UTType.image.identifier
        visualProgress = provider.loadFileRepresentation(forTypeIdentifier: type) { [weak self] url, error in
            // Copy inside this callback: the provider deletes its representation when it returns.
            let folder = DiscourseClipExporter.directory.appendingPathComponent("Visual-" + UUID().uuidString)
            let result: Result<URL, Error>
            do {
                guard let url else { throw error ?? DiscourseClipExporter.error("CLIP_VISUAL_FAILED") }
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let copy = folder.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.copyItem(at: url, to: copy)
                result = .success(copy)
            } catch { result = .failure(error) }
            DispatchQueue.main.async {
                guard let self, self.operation == token else { try? FileManager.default.removeItem(at: folder); return }
                switch result {
                case .success(let copy):
                    self.clearVisual(); self.visualDirectory = folder; self.visual = copy; self.download()
                case .failure(let error):
                    try? FileManager.default.removeItem(at: folder); self.fail(error)
                }
            }
        }
    }
}

/// One operation owns the progress surface while the export drawer keeps its options.
final class DiscourseClipProgressController: UIViewController {
    var onCancel: (() -> Void)?
    private let isVideo: Bool
    private let percentage = UILabel()
    private let message = UILabel()
    private let progressBar = UIProgressView(progressViewStyle: .default)
    private let ring = CAShapeLayer()
    private let iconContainer = UIView()

    init(isVideo: Bool) {
        self.isVideo = isVideo
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        isModalInPresentation = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() { view = DiscourseClipProgressBackground() }

    override func viewDidLoad() {
        super.viewDidLoad()
        let colors = DiscourseColors.current
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -32),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -64),
            stack.topAnchor.constraint(greaterThanOrEqualTo: scroll.contentLayoutGuide.topAnchor, constant: 32),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -32)
        ])
        let center = stack.centerYAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerYAnchor, constant: 30)
        center.priority = .defaultHigh
        center.isActive = true

        iconContainer.heightAnchor.constraint(equalToConstant: 150).isActive = true
        stack.addArrangedSubview(iconContainer)
        let icon = UIImageView(image: UIImage(systemName: isVideo ? "movieclapper" : "waveform") ?? UIImage(systemName: "film"))
        icon.tintColor = colors.accent
        icon.contentMode = .scaleAspectFit
        icon.isAccessibilityElement = false
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(icon)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 68), icon.heightAnchor.constraint(equalToConstant: 68),
            icon.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor)
        ])
        let rail = CAShapeLayer()
        rail.path = UIBezierPath(ovalIn: CGRect(x: 5, y: 5, width: 140, height: 140)).cgPath
        rail.strokeColor = colors.primaryText.withAlphaComponent(0.18).cgColor
        rail.fillColor = UIColor.clear.cgColor
        rail.lineWidth = 6
        iconContainer.layer.addSublayer(rail)
        ring.path = UIBezierPath(arcCenter: CGPoint(x: 75, y: 75), radius: 70,
            startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: true).cgPath
        ring.strokeColor = colors.accent.cgColor
        ring.fillColor = UIColor.clear.cgColor
        ring.lineWidth = 6
        ring.lineCap = .round
        ring.strokeEnd = 0
        iconContainer.layer.addSublayer(ring)

        let heading = UILabel()
        heading.text = isVideo ? NSLocalizedString("CLIP_CREATING_VIDEO", comment: "Export progress title")
            : NSLocalizedString("CLIP_CREATING_AUDIO", comment: "Export progress title")
        heading.font = .preferredFont(forTextStyle: .title1)
        heading.textColor = colors.primaryText
        heading.accessibilityTraits = .header
        heading.accessibilityIdentifier = "clipExportTitle"
        message.font = .preferredFont(forTextStyle: .body)
        message.textColor = colors.primaryText.withAlphaComponent(0.7)
        percentage.font = .preferredFont(forTextStyle: .largeTitle)
        percentage.textColor = colors.accent
        percentage.accessibilityIdentifier = "clipExportPercentage"
        percentage.accessibilityTraits = .updatesFrequently
        for label in [heading, message, percentage] {
            label.numberOfLines = 0
            label.textAlignment = .center
            label.adjustsFontForContentSizeCategory = true
            stack.addArrangedSubview(label)
        }
        progressBar.progressTintColor = colors.accent
        progressBar.trackTintColor = colors.primaryText.withAlphaComponent(0.25)
        progressBar.isAccessibilityElement = false // The percentage label carries the value.
        stack.addArrangedSubview(progressBar)
        stack.setCustomSpacing(40, after: progressBar)
        var config = UIButton.Configuration.filled()
        config.title = NSLocalizedString("BUTTON_CANCEL", comment: "Cancel export")
        config.baseBackgroundColor = colors.accent
        config.baseForegroundColor = .white
        config.cornerStyle = .medium
        config.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        let cancel = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in self?.onCancel?() })
        cancel.accessibilityLabel = NSLocalizedString("BUTTON_CANCEL", comment: "Cancel export")
        cancel.accessibilityIdentifier = "clipExportCancel"
        stack.addArrangedSubview(cancel)
        update(progress: 0)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        for layer in iconContainer.layer.sublayers ?? [] where layer is CAShapeLayer {
            layer.frame = CGRect(x: (iconContainer.bounds.width - 150) / 2, y: 0, width: 150, height: 150)
        }
    }

    func update(progress: Double, status: String? = nil) {
        loadViewIfNeeded()
        let value = progress.isFinite ? min(1, max(0, progress)) : 0
        percentage.text = String(format: NSLocalizedString("CLIP_PROGRESS_PERCENT", comment: "Export percentage"), Int(value * 100))
        message.text = status ?? NSLocalizedString("CLIP_CREATING_DESCRIPTION", comment: "Export progress explanation")
        progressBar.progress = Float(value)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.strokeEnd = value
        CATransaction.commit()
    }
}

private final class DiscourseClipProgressBackground: UIView {
    override func draw(_ rect: CGRect) {
        let colors = DiscourseColors.current
        colors.appBackground.setFill()
        UIRectFill(rect)
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let gradientColors = [colors.accent.withAlphaComponent(0.08).cgColor, colors.appBackground.cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: gradientColors, locations: [0, 1]) {
            context.drawRadialGradient(gradient, startCenter: CGPoint(x: bounds.midX, y: bounds.midY), startRadius: 0,
                endCenter: CGPoint(x: bounds.midX, y: bounds.midY), endRadius: bounds.height * 0.6, options: [])
        }
        for index in 0..<3 {
            let wave = UIBezierPath()
            let y = bounds.height * 0.12 + CGFloat(index) * 32
            wave.move(to: CGPoint(x: -20, y: y + 32))
            wave.addCurve(to: CGPoint(x: bounds.width + 20, y: y),
                controlPoint1: CGPoint(x: bounds.width * 0.3, y: y - (index == 1 ? 70 : 130)),
                controlPoint2: CGPoint(x: bounds.width * 0.6, y: y + (index == 2 ? -100 : 130)))
            colors.accent.withAlphaComponent(0.35 - CGFloat(index) * 0.08).setStroke()
            wave.lineWidth = 1.5
            wave.stroke()
            wave.addLine(to: CGPoint(x: bounds.width + 20, y: bounds.height))
            wave.addLine(to: CGPoint(x: -20, y: bounds.height))
            wave.close()
            context.saveGState()
            wave.addClip()
            let waveColors = [colors.accent.withAlphaComponent(0.12).cgColor, UIColor.clear.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: waveColors, locations: [0, 1]) {
                context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: y - 40),
                    end: CGPoint(x: 0, y: y + 100), options: [.drawsBeforeStartLocation])
            }
            context.restoreGState()
        }
    }
}
