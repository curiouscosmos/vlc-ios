/*
 * Copyright (c) 2026 Sandalbar Enterprises, Inc.
 * Part of Rajneesh Discourse. GPLv2 or later; see COPYING.
 */
import UIKit

final class DiscourseClipSaveController: UITableViewController, UIDocumentPickerDelegate {
    private let track: DiscourseAudio
    private let range: DiscourseClipRange
    private let exporter = DiscourseClipExporter()
    private var timer: Timer?
    private var busy = false
    private var exporting = false
    private var operation = UUID()
    private var status: String?

    init(track: DiscourseAudio, range: DiscourseClipRange) {
        self.track = track
        self.range = range
        super.init(style: .insetGrouped)
        title = NSLocalizedString("CLIP_SAVE", comment: "")
        navigationItem.largeTitleDisplayMode = .never
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { timer?.invalidate(); NotificationCenter.default.removeObserver(self); exporter.cancel(); exporter.clean() }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = DiscourseColors.current.surfaceStart
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 86
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        NotificationCenter.default.addObserver(self, selector: #selector(background), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 2 }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = DiscourseColors.current.surfaceEnd
        cell.textLabel?.textColor = DiscourseColors.current.primaryText
        cell.detailTextLabel?.textColor = DiscourseColors.current.primaryText.withAlphaComponent(0.65)
        let share = indexPath.row == 0
        cell.textLabel?.text = share ? NSLocalizedString("CLIP_SHARE_IN_APP", comment: "") : NSLocalizedString("CLIP_DOWNLOAD", comment: "")
        cell.detailTextLabel?.text = share ? NSLocalizedString("CLIP_SHARE_DESCRIPTION", comment: "") : status ?? NSLocalizedString("CLIP_DOWNLOAD_DESCRIPTION", comment: "")
        cell.imageView?.image = UIImage(systemName: share ? "square.and.arrow.up" : "arrow.down.to.line")
        cell.imageView?.tintColor = DiscourseColors.current.accent
        cell.accessoryType = .disclosureIndicator
        cell.textLabel?.font = .preferredFont(forTextStyle: .headline)
        cell.detailTextLabel?.font = .preferredFont(forTextStyle: .subheadline)
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.detailTextLabel?.adjustsFontForContentSizeCategory = true
        cell.detailTextLabel?.numberOfLines = 0
        cell.accessibilityLabel = cell.textLabel?.text
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.row == 0 {
            let alert = UIAlertController(title: NSLocalizedString("CLIP_COMING_SOON", comment: ""), message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("BUTTON_OK", comment: ""), style: .default))
            present(alert, animated: true)
        } else if !busy { download() }
    }
    private func download() {
        busy = true
        exporting = false
        isModalInPresentation = true
        operation = UUID()
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
            exporter.export(source: source, sourceExtension: track.audioURL?.pathExtension, title: track.title, range: range) { [weak self] result in
                guard let self, self.operation == token else { return }
                self.busy = false
                self.isModalInPresentation = false
                switch result {
                case .success(let url):
                    let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
                    picker.delegate = self
                    self.present(picker, animated: true)
                case .failure: self.fail()
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
    private func fail() {
        timer?.invalidate(); timer = nil
        busy = false
        isModalInPresentation = false
        status = NSLocalizedString("CLIP_FAILED", comment: "")
        tableView.reloadData()
    }
    @objc private func background() {
        guard busy else { return }
        operation = UUID(); exporter.cancel(); exporter.clean(); fail()
    }
    @objc private func cancel() {
        operation = UUID(); timer?.invalidate(); timer = nil; exporter.cancel()
        dismiss(animated: true)
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finished() }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { finished() }
    private func finished() { exporter.clean(); status = nil; tableView.reloadData() }
}
