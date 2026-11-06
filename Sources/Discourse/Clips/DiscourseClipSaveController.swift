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
    private var exportCC = false
    private var visual: URL?
    private var visualDirectory: URL?
    private var captionTask: Task<Void, Never>?
    private var visualProgress: Progress?
    private var request: DiscourseClipExportRequest?

    init(track: DiscourseAudio, range: DiscourseClipRange) {
        self.track = track
        self.range = range
        super.init(style: .insetGrouped)
        title = NSLocalizedString("CLIP_SAVE", comment: "")
        navigationItem.largeTitleDisplayMode = .never
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { visualProgress?.cancel(); captionTask?.cancel(); if let visualDirectory { try? FileManager.default.removeItem(at: visualDirectory) }; timer?.invalidate(); NotificationCenter.default.removeObserver(self); exporter.cancel(); exporter.clean() }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = DiscourseColors.current.surfaceStart
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 86
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        NotificationCenter.default.addObserver(self, selector: #selector(background), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { track.captionURL == nil ? 3 : 4 }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = DiscourseColors.current.surfaceEnd
        cell.textLabel?.textColor = DiscourseColors.current.primaryText
        cell.detailTextLabel?.textColor = DiscourseColors.current.primaryText.withAlphaComponent(0.65)
        if indexPath.row == 3 {
            cell.textLabel?.text = NSLocalizedString("CLIP_EXPORT_CC", comment: "")
            cell.textLabel?.font = .preferredFont(forTextStyle: .headline)
            cell.textLabel?.adjustsFontForContentSizeCategory = true
            cell.textLabel?.numberOfLines = 0
            let toggle = UISwitch()
            toggle.isOn = exportCC
            toggle.isEnabled = !busy
            toggle.accessibilityLabel = cell.textLabel?.text
            toggle.addTarget(self, action: #selector(captionsChanged(_:)), for: .valueChanged)
            cell.accessoryView = toggle
            cell.selectionStyle = .none
            return cell
        }
        let share = indexPath.row == 0
        let video = indexPath.row == 2
        cell.textLabel?.text = share ? NSLocalizedString("CLIP_SHARE_TRACK_LINK", comment: "") : NSLocalizedString("CLIP_DOWNLOAD", comment: "")
        cell.detailTextLabel?.text = share ? NSLocalizedString("CLIP_SHARE_DESCRIPTION", comment: "") : status ?? NSLocalizedString("CLIP_DOWNLOAD_DESCRIPTION", comment: "")
        if video {
            cell.textLabel?.text = NSLocalizedString("CLIP_EXPORT_VIDEO", comment: "")
            cell.detailTextLabel?.text = status ?? NSLocalizedString("CLIP_VIDEO_DESCRIPTION", comment: "")
        }
        cell.isUserInteractionEnabled = !busy
        cell.contentView.alpha = busy ? 0.5 : 1
        cell.accessibilityTraits = busy ? [.button, .notEnabled] : .button
        cell.imageView?.image = UIImage(systemName: share ? "square.and.arrow.up" : video ? "video" : "arrow.down.to.line")
        cell.imageView?.tintColor = DiscourseColors.current.accent
        cell.accessoryType = .disclosureIndicator
        cell.textLabel?.font = .preferredFont(forTextStyle: .headline)
        cell.detailTextLabel?.font = .preferredFont(forTextStyle: .subheadline)
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.adjustsFontForContentSizeCategory = true
        cell.detailTextLabel?.numberOfLines = 0
        cell.accessibilityLabel = cell.textLabel?.text
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !busy else { return }
        if indexPath.row == 0 {
            guard let url = DiscourseDeepLink.clipURL(discourseID: track.discourseID, audioID: track.id,
                                                       start: range.start, end: range.end) else { return }
            let activity = UIActivityViewController(activityItems: [track.title, url], applicationActivities: nil)
            activity.popoverPresentationController?.sourceView = tableView
            activity.popoverPresentationController?.sourceRect = tableView.rectForRow(at: indexPath)
            present(activity, animated: true)
        } else if indexPath.row == 2 {
            var configuration = PHPickerConfiguration()
            configuration.selectionLimit = 1
            configuration.filter = .any(of: [.images, .videos])
            let picker = PHPickerViewController(configuration: configuration)
            picker.delegate = self
            present(picker, animated: true)
        } else if indexPath.row == 1 {
            clearVisual()
            download()
        }
    }
    private func download() {
        busy = true
        exporting = false
        isModalInPresentation = true
        operation = UUID()
        let mixer = DiscourseAudioMixer.shared
        request = DiscourseClipExportRequest(source: URL(fileURLWithPath: "/"), sourceExtension: track.audioURL?.pathExtension,
            title: track.title, range: range, visual: visual, noise: PlaybackService.sharedInstance().noiseReductionEnabled,
            music: mixer.selectedURL, musicEnabled: mixer.isEnabled, musicVolume: Float(mixer.volume) / 100, musicLoops: mixer.isLooping)
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
            status = NSLocalizedString("CLIP_EXPORTING", comment: "")
            tableView.reloadData()
            let token = operation
            guard let snapshot = request else { fail(); return }
            captionTask = Task { [weak self] in
                guard let self else { return }
                do {
                    var captions: [DiscourseCaption]?
                    if self.exportCC {
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
                        musicLoops: snapshot.musicLoops, captions: captions)
                    self.exporter.export(request, progress: { [weak self] fraction in
                        guard let self, self.operation == token else { return }
                        self.status = String(format: NSLocalizedString("CLIP_EXPORT_PROGRESS", comment: ""), Int(fraction * 100))
                        self.tableView.reloadData()
                    }) { [weak self] result in
                        guard let self, self.operation == token else { return }
                        // Keep options disabled until Files relinquishes the temporary output.
                        switch result {
                        case .success(let urls):
                            let picker = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
                            picker.delegate = self
                            self.present(picker, animated: true)
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
                status = String(format: NSLocalizedString("CLIP_DOWNLOADING", comment: ""), Int(progress * 100))
                tableView.reloadData()
            case .downloaded: fail()
            }
        }
    }
    private func fail(_ error: Error? = nil) {
        timer?.invalidate(); timer = nil
        busy = false
        isModalInPresentation = false
        status = error?.localizedDescription ?? NSLocalizedString("CLIP_FAILED", comment: "")
        tableView.reloadData()
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
    @objc private func captionsChanged(_ sender: UISwitch) { exportCC = sender.isOn }
    private func clearVisual() {
        if let visualDirectory { try? FileManager.default.removeItem(at: visualDirectory) }
        visualDirectory = nil; visual = nil
    }
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else { return }
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
