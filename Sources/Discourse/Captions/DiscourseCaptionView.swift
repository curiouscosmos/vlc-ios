/* Copyright (c) 2026 Sandalbar Enterprises, Inc. GPLv2 or later; see COPYING. */
import UIKit

private final class DiscourseCaptionTable: UITableView {
    var userScrolled: (() -> Void)?
    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        userScrolled?()
        return super.accessibilityScroll(direction)
    }
}

final class DiscourseCaptionView: UIView, UITableViewDataSource, UITableViewDelegate {
    var phraseTapped: ((DiscourseCaption) -> Void)?
    var retry: (() -> Void)?
    private(set) var captions: [DiscourseCaption] = []
    private let table = DiscourseCaptionTable(frame: .zero, style: .plain)
    private let message = UILabel()
    private let retryButton = UIButton(type: .system)
    private let followButton = UIButton(type: .system)
    private var activeIndex: Int?
    private var following = true
    private var clipRange: DiscourseClipRange?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = DiscourseColors.current.surfaceStart
        layer.cornerRadius = 14
        clipsToBounds = true
        table.userScrolled = { [weak self] in self?.stopFollowing() }
        table.dataSource = self
        table.delegate = self
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.estimatedRowHeight = 80
        table.rowHeight = UITableView.automaticDimension
        table.accessibilityIdentifier = "discourseTranscript"
        message.font = .preferredFont(forTextStyle: .body)
        message.adjustsFontForContentSizeCategory = true
        message.numberOfLines = 0
        message.textAlignment = .center
        retryButton.setTitle(NSLocalizedString("CC_RETRY", comment: "Retry captions"), for: .normal)
        retryButton.accessibilityIdentifier = "captionRetry"
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        followButton.setTitle(NSLocalizedString("CC_FOLLOW", comment: "Follow current caption"), for: .normal)
        followButton.addTarget(self, action: #selector(followTapped), for: .touchUpInside)
        for child in [table, message, retryButton, followButton] {
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
        }
        NSLayoutConstraint.activate([
            table.leadingAnchor.constraint(equalTo: leadingAnchor), table.trailingAnchor.constraint(equalTo: trailingAnchor),
            table.topAnchor.constraint(equalTo: topAnchor), table.bottomAnchor.constraint(equalTo: followButton.topAnchor),
            followButton.bottomAnchor.constraint(equalTo: bottomAnchor), followButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            followButton.heightAnchor.constraint(equalToConstant: 44),
            message.centerYAnchor.constraint(equalTo: centerYAnchor), message.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            message.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            retryButton.topAnchor.constraint(equalTo: message.bottomAnchor, constant: 8), retryButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            retryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
        showLoading()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if following { scrollToActive() }
    }

    func showLoading() {
        captions = []
        activeIndex = nil
        following = true
        table.reloadData()
        message.text = NSLocalizedString("CC_LOADING", comment: "Loading captions")
        message.isHidden = false
        retryButton.isHidden = true
        followButton.isHidden = true
        applyTheme()
    }

    func showFailure() {
        message.text = NSLocalizedString("CC_FAILED", comment: "Caption load failure")
        message.isHidden = false
        retryButton.isHidden = false
    }

    func display(_ captions: [DiscourseCaption]) {
        self.captions = captions
        message.isHidden = true
        retryButton.isHidden = true
        table.reloadData()
    }

    func update(time: Double, range: DiscourseClipRange?) {
        let next = DiscourseCaptions.activeIndex(in: captions, at: time)
        let positionChanged = next != activeIndex
        let rangeChanged = clipRange?.start != range?.start || clipRange?.end != range?.end
        clipRange = range
        guard positionChanged || rangeChanged else { return }
        activeIndex = next
        // Only visible phrases need repainting; never rebuild the entire transcript on a tick.
        for cell in table.visibleCells {
            if let index = table.indexPath(for: cell)?.row { configure(cell, at: index) }
        }
        if following && positionChanged { scrollToActive() }
    }

    func applyTheme() {
        backgroundColor = DiscourseColors.current.surfaceStart
        message.textColor = DiscourseColors.current.primaryText
        retryButton.tintColor = DiscourseColors.current.accent
        followButton.tintColor = DiscourseColors.current.accent
        table.reloadData()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { captions.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "phrase") ?? UITableViewCell(style: .default, reuseIdentifier: "phrase")
        configure(cell, at: indexPath.row)
        return cell
    }

    private func configure(_ cell: UITableViewCell, at index: Int) {
        let phrase = captions[index]
        cell.textLabel?.text = phrase.text
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.font = .preferredFont(forTextStyle: .title2)
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.textLabel?.textColor = index == activeIndex ? DiscourseColors.current.accent : DiscourseColors.current.primaryText.withAlphaComponent(0.65)
        let selected = clipRange.map { phrase.start < $0.end && phrase.end > $0.start } ?? false
        cell.backgroundColor = selected ? DiscourseColors.current.accent.withAlphaComponent(0.15) : .clear
        cell.selectionStyle = .none
        cell.accessibilityIdentifier = "captionPhrase_\(index)"
        cell.accessibilityTraits = clipRange == nil ? .staticText : .button
        cell.accessibilityValue = index == activeIndex ? NSLocalizedString("CC_CURRENT", comment: "Current phrase") : nil
        cell.accessibilityHint = clipRange == nil ? nil : NSLocalizedString("CC_SELECT_HINT", comment: "Caption clipping hint")
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if clipRange != nil { stopFollowing() }
        phraseTapped?(captions[indexPath.row])
    }
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { stopFollowing() }
    private func stopFollowing() {
        following = false
        followButton.isHidden = captions.isEmpty
    }
    private func scrollToActive() {
        guard window != nil, let activeIndex, !table.isDragging, !table.isDecelerating else { return }
        table.scrollToRow(at: IndexPath(row: activeIndex, section: 0), at: .middle, animated: false)
    }
    @objc private func retryTapped() { retry?() }
    @objc private func followTapped() { following = true; followButton.isHidden = true; scrollToActive() }
}
