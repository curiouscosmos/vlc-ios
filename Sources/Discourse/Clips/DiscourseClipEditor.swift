/*
 * Copyright (c) 2026 Sandalbar Enterprises, Inc.
 * Part of Rajneesh Discourse. GPLv2 or later; see COPYING.
 */

import UIKit

struct DiscourseClipRange: Equatable {
    let duration: Double
    var start: Double
    var end: Double

    init(duration: Double, position: Double) {
        self.duration = duration.isFinite ? max(1, duration) : 1
        start = min(max(0, position.isFinite ? position : 0), self.duration - 1)
        end = min(self.duration, start + 60)
    }

    mutating func moveStart(to value: Double) {
        guard value.isFinite else { return }
        start = min(max(0, value), end - 1)
    }

    mutating func moveEnd(to value: Double) {
        guard value.isFinite else { return }
        end = max(start + 1, min(duration, value))
    }

    static func time(_ seconds: Double) -> String {
        let value = Int(max(0, seconds))
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
            : String(format: "%d:%02d", value / 60, value % 60)
    }
}

/// A preview start is an explicit, one-shot seek, never a correction of VLC's
/// asynchronous position reports. Wait for resumed audio before issuing it.
struct DiscourseClipPreview {
    private(set) var pendingStart: Double?
    private var resumeAnchor: Double?

    mutating func requestStart(at seconds: Double) {
        pendingStart = seconds
        resumeAnchor = nil
    }

    mutating func seekTarget(position: Double, isPlaying: Bool, isInteracting: Bool) -> Double? {
        guard isPlaying, !isInteracting else { resumeAnchor = nil; return nil }
        guard let target = pendingStart else { return nil }
        guard let anchor = resumeAnchor else { resumeAnchor = position; return nil }
        guard position >= anchor + 0.5 else { return nil }
        pendingStart = nil
        resumeAnchor = nil
        return target
    }
}

private final class DiscourseClipHandle: UIControl {
    var adjust: ((Double) -> Void)?
    override func accessibilityIncrement() { adjust?(1) }
    override func accessibilityDecrement() { adjust?(-1) }
}

private final class DiscourseClipTimeline: UISlider {
    override func trackRect(forBounds bounds: CGRect) -> CGRect {
        let rect = super.trackRect(forBounds: bounds)
        return CGRect(x: rect.minX, y: bounds.midY - 2, width: rect.width, height: 4)
    }
}

final class DiscourseClipEditor: UIView {
    static func preferredHeight(for traits: UITraitCollection) -> CGFloat {
        UIFontMetrics.default.scaledValue(for: 168, compatibleWith: traits)
            + (traits.preferredContentSizeCategory.isAccessibilityCategory ? 64 : 0)
    }

    var range: DiscourseClipRange { didSet { update() } }
    var cut: (() -> Void)?
    var seek: ((Double) -> Void)?
    /// Called whenever the start bracket moves so the playhead can follow it.
    var startDidChange: ((Double) -> Void)?
    /// True while the user is dragging a bracket or the timeline thumb, so the
    /// player does not fight the gesture with automatic range corrections.
    var isUserInteracting: Bool { timeline.isTracking || draggingHandle }
    private var draggingHandle = false
    private let timeline = DiscourseClipTimeline()
    private let startHandle = DiscourseClipHandle()
    private let endHandle = DiscourseClipHandle()
    private let selection = UIView()
    private let rail = UIView()
    private let startTime = UILabel()
    private let endTime = UILabel()
    private let separator = UILabel()
    private let trackStart = UILabel()
    private let trackEnd = UILabel()
    private let positionLabel = UILabel()
    private let positionLine = UIView()
    private var adjustmentButtons: [UIButton] = []
    private let summary = UILabel()
    private let cutButton = UIButton(type: .system)

    init(range: DiscourseClipRange) {
        self.range = range
        super.init(frame: .zero)
        backgroundColor = DiscourseColors.current.surfaceStart.withAlphaComponent(0.9)
        summary.textColor = DiscourseColors.current.primaryText
        layer.cornerRadius = 16
        layer.borderWidth = 1
        layer.borderColor = UIColor.separator.cgColor
        for label in [startTime, endTime, separator, trackStart, trackEnd, positionLabel] {
            label.font = .preferredFont(forTextStyle: .caption1, compatibleWith: .current)
            label.adjustsFontForContentSizeCategory = true
            label.textColor = DiscourseColors.current.primaryText
            label.textAlignment = .center
        }
        separator.text = "—"
        trackStart.text = "00:00"
        trackStart.textAlignment = .left
        trackEnd.text = DiscourseClipRange.time(range.duration)
        trackEnd.textAlignment = .right
        positionLabel.backgroundColor = DiscourseColors.current.primaryText.withAlphaComponent(0.12)
        positionLabel.accessibilityIdentifier = "clipPreviewTime"
        positionLabel.layer.cornerRadius = 7
        positionLabel.clipsToBounds = true
        positionLine.backgroundColor = DiscourseColors.current.primaryText
        positionLine.isUserInteractionEnabled = false
        summary.font = .preferredFont(forTextStyle: .subheadline, compatibleWith: .current)
        summary.adjustsFontForContentSizeCategory = true
        summary.numberOfLines = 0
        summary.textAlignment = .center
        timeline.minimumTrackTintColor = .clear
        timeline.maximumTrackTintColor = .clear
        timeline.minimumValue = 0
        timeline.maximumValue = Float(range.duration)
        rail.backgroundColor = .systemGray
        rail.layer.cornerRadius = 2
        rail.isUserInteractionEnabled = false
        let thumb = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { context in
            DiscourseColors.current.primaryText.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        timeline.setThumbImage(thumb, for: .normal)
        timeline.accessibilityLabel = NSLocalizedString("PLAYBACK_POSITION", comment: "")
        timeline.addTarget(self, action: #selector(scrub), for: .valueChanged)
        selection.backgroundColor = DiscourseColors.current.accent
        selection.isUserInteractionEnabled = false
        [startTime, endTime, separator, rail, timeline, selection, positionLine, positionLabel, trackStart, trackEnd, startHandle, endHandle, summary, cutButton].forEach(addSubview)
        let adjustments = [
            ("CLIP_START_DECREASE", NSLocalizedString("CLIP_START_DECREASE", comment: "Decrease clip start by one second")),
            ("CLIP_START_INCREASE", NSLocalizedString("CLIP_START_INCREASE", comment: "Increase clip start by one second")),
            ("CLIP_END_DECREASE", NSLocalizedString("CLIP_END_DECREASE", comment: "Decrease clip end by one second")),
            ("CLIP_END_INCREASE", NSLocalizedString("CLIP_END_INCREASE", comment: "Increase clip end by one second"))
        ]
        for (index, adjustment) in adjustments.enumerated() {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: index % 2 == 0 ? "minus" : "plus",
                                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)), for: .normal)
            let outline = UIView(frame: CGRect(x: 10, y: 10, width: 24, height: 24))
            outline.tag = 100
            outline.isUserInteractionEnabled = false
            outline.layer.cornerRadius = 7
            outline.layer.borderWidth = 1
            outline.layer.borderColor = DiscourseColors.current.primaryText.withAlphaComponent(0.25).cgColor
            outline.backgroundColor = DiscourseColors.current.primaryText.withAlphaComponent(0.04)
            button.insertSubview(outline, at: 0)
            button.tintColor = DiscourseColors.current.primaryText
            button.accessibilityLabel = adjustment.1
            button.accessibilityIdentifier = adjustment.0
            button.tag = index
            button.addTarget(self, action: #selector(adjustEndpoint(_:)), for: .touchUpInside)
            adjustmentButtons.append(button)
            addSubview(button)
        }
        for (handle, key) in [(startHandle, NSLocalizedString("CLIP_START", comment: "")), (endHandle, NSLocalizedString("CLIP_END", comment: ""))] {
            handle.isAccessibilityElement = true
            handle.accessibilityTraits = .adjustable
            handle.accessibilityLabel = key
            let bar = UIView()
            bar.backgroundColor = DiscourseColors.current.primaryText
            bar.layer.cornerRadius = 4
            bar.frame = CGRect(x: 18, y: 10, width: 8, height: 24)
            bar.isUserInteractionEnabled = false
            handle.addSubview(bar)
            handle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(drag(_:))))
        }
        startHandle.adjust = { [weak self] delta in
            guard let self else { return }
            self.range.moveStart(to: self.range.start + delta)
            self.startDidChange?(self.range.start)
        }
        endHandle.adjust = { [weak self] delta in
            guard let self else { return }; self.range.moveEnd(to: self.range.end + delta)
        }
        var config = UIButton.Configuration.filled()
        config.title = NSLocalizedString("CLIP_CUT", comment: "")
        config.image = UIImage(systemName: "scissors")
        config.imagePadding = 8
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        config.titleLineBreakMode = .byClipping
        config.cornerStyle = .capsule
        config.baseBackgroundColor = DiscourseColors.current.accent
        cutButton.configuration = config
        cutButton.accessibilityLabel = config.title
        cutButton.addTarget(self, action: #selector(cutTapped), for: .touchUpInside)
        setPosition(range.start)
        update()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = max(1, UIFontMetrics.default.scaledValue(for: 168, compatibleWith: traitCollection) / 168)
        let stacked = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        let half = stacked ? bounds.width - 24 : (bounds.width - 40) / 2
        let rowHeight = stacked ? max(44, 22 * scale) : 44 * scale
        let labelWidth = max(0, half - 88)
        for (index, label) in [startTime, endTime].enumerated() {
            let x = stacked ? 12 : 12 + CGFloat(index) * (half + 16)
            let y = stacked ? CGFloat(index) * rowHeight : 0
            adjustmentButtons[index * 2].frame = CGRect(x: x, y: y, width: 44, height: rowHeight)
            label.frame = CGRect(x: x + 44, y: y, width: labelWidth, height: rowHeight)
            label.adjustsFontSizeToFitWidth = true
            adjustmentButtons[index * 2 + 1].frame = CGRect(x: x + half - 44, y: y, width: 44, height: rowHeight)
        }
        separator.isHidden = stacked
        separator.frame = CGRect(x: bounds.midX - 8, y: 0, width: 16, height: rowHeight)
        let timelineY = stacked ? max(52 * scale, rowHeight * 2 + positionLabel.intrinsicContentSize.height + 8) : 52 * scale
        timeline.frame = CGRect(x: 22, y: timelineY, width: bounds.width - 44, height: 44)
        let track = timeline.convert(timeline.trackRect(forBounds: timeline.bounds), to: self)
        let startX = track.minX + track.width * range.start / range.duration
        let endX = track.minX + track.width * range.end / range.duration
        rail.frame = track
        selection.frame = CGRect(x: startX, y: track.midY - 2, width: endX - startX, height: 4)
        selection.layer.cornerRadius = 2
        startHandle.frame = CGRect(x: startX - 22, y: track.midY - 22, width: 44, height: 44)
        endHandle.frame = CGRect(x: endX - 22, y: track.midY - 22, width: 44, height: 44)
        let thumb = timeline.convert(timeline.thumbRect(forBounds: timeline.bounds, trackRect: timeline.trackRect(forBounds: timeline.bounds), value: timeline.value), to: self)
        positionLabel.sizeToFit()
        let labelHeight = positionLabel.bounds.height + 8
        let width = positionLabel.bounds.width + 8
        positionLabel.frame = CGRect(x: min(bounds.width - width - 8, max(8, thumb.midX - width / 2)), y: track.midY - labelHeight - 12, width: width, height: labelHeight)
        positionLine.frame = CGRect(x: thumb.midX - 0.5, y: track.midY, width: 1, height: 32)
        bringSubviewToFront(timeline)
        bringSubviewToFront(startHandle)
        bringSubviewToFront(endHandle)
        trackStart.frame = CGRect(x: track.minX, y: track.maxY + 14, width: track.width / 2, height: 22 * scale)
        trackEnd.frame = CGRect(x: track.midX, y: track.maxY + 14, width: track.width / 2, height: 22 * scale)
        let buttonWidth = min(bounds.width - 24, max(100, cutButton.intrinsicContentSize.width))
        let cutHeight = max(44, cutButton.intrinsicContentSize.height)
        if stacked {
            let summaryHeight = summary.sizeThatFits(CGSize(width: bounds.width - 24, height: .greatestFiniteMagnitude)).height
            summary.frame = CGRect(x: 12, y: trackEnd.frame.maxY + 8, width: bounds.width - 24, height: summaryHeight)
            cutButton.frame = CGRect(x: bounds.width - buttonWidth - 12, y: summary.frame.maxY + 8, width: buttonWidth, height: cutHeight)
        } else {
            summary.frame = CGRect(x: 12, y: 118 * scale, width: bounds.width - buttonWidth - 36, height: bounds.height - 122 * scale)
            cutButton.frame = CGRect(x: bounds.width - buttonWidth - 12, y: summary.frame.midY - cutHeight / 2, width: buttonWidth, height: cutHeight)
        }
        for button in adjustmentButtons {
            button.viewWithTag(100)?.center = CGPoint(x: button.bounds.midX, y: button.bounds.midY)
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if !isHidden && point.y >= startHandle.frame.minY && point.y <= startHandle.frame.maxY {
            let distanceStart = abs(point.x - startHandle.center.x)
            let distanceEnd = abs(point.x - endHandle.center.x)
            if min(distanceStart, distanceEnd) <= 22 { return distanceStart < distanceEnd ? startHandle : endHandle }
        }
        return super.hitTest(point, with: event)
    }

    func setPosition(_ seconds: Double) {
        if !timeline.isTracking { timeline.value = Float(seconds) }
        positionLabel.text = DiscourseClipRange.time(Double(timeline.value))
        setNeedsLayout()
    }

    private func update() {
        startTime.text = DiscourseClipRange.time(range.start)
        endTime.text = DiscourseClipRange.time(range.end)
        let enabled = [range.start >= 1, range.end - range.start >= 2,
                       range.end - range.start >= 2, range.duration - range.end >= 1]
        for (button, enabled) in zip(adjustmentButtons, enabled) { button.isEnabled = enabled }
        summary.text = String(format: NSLocalizedString("CLIP_SELECTED", comment: ""), DiscourseClipRange.time(range.end - range.start))
        startHandle.accessibilityValue = DiscourseClipRange.time(range.start)
        endHandle.accessibilityValue = DiscourseClipRange.time(range.end)
        setNeedsLayout()
    }

    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began, .changed: draggingHandle = true
        case .ended, .cancelled, .failed: draggingHandle = false
        default: break
        }
        guard gesture.state == .began || gesture.state == .changed || gesture.state == .ended else { return }
        let track = timeline.convert(timeline.trackRect(forBounds: timeline.bounds), to: self)
        let value = ((gesture.location(in: self).x - track.minX) / max(1, track.width) * range.duration).rounded()
        if gesture.view === startHandle {
            range.moveStart(to: value)
            if gesture.state == .ended { startDidChange?(range.start) }
        } else {
            range.moveEnd(to: value)
        }
    }

    @objc private func adjustEndpoint(_ button: UIButton) {
        let delta: Double = button.tag % 2 == 0 ? -1 : 1
        if button.tag < 2 { startHandle.adjust?(delta) } else { endHandle.adjust?(delta) }
    }

    @objc private func scrub() {
        timeline.value = Float(min(range.end, max(range.start, Double(timeline.value))))
        setPosition(Double(timeline.value))
        seek?(Double(timeline.value))
    }
    @objc private func cutTapped() { cut?() }
}

/// Download consent comes before entering the range editor.
final class DiscourseClipDownloadPrompt: UIViewController {
    private let download: () -> Void

    init(download: @escaping () -> Void) {
        self.download = download
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        view.accessibilityViewIsModal = true
        let card = UIView()
        card.backgroundColor = DiscourseColors.current.surfaceStart
        card.layer.cornerRadius = 20
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)
        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.tintColor = DiscourseColors.current.primaryText
        close.accessibilityLabel = NSLocalizedString("BUTTON_CLOSE", comment: "")
        close.accessibilityIdentifier = "clipDownloadClose"
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        let message = UILabel()
        message.text = NSLocalizedString("CLIP_DOWNLOAD_REQUIRED", comment: "")
        message.textColor = DiscourseColors.current.primaryText
        message.font = .preferredFont(forTextStyle: .body)
        message.adjustsFontForContentSizeCategory = true
        message.numberOfLines = 0
        message.textAlignment = .center
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.title = NSLocalizedString("BUTTON_DOWNLOAD", comment: "")
        configuration.baseBackgroundColor = DiscourseColors.current.accent
        button.configuration = configuration
        button.accessibilityLabel = configuration.title
        button.accessibilityIdentifier = "clipDownloadConfirm"
        button.addTarget(self, action: #selector(downloadTapped), for: .touchUpInside)
        for child in [close, message, button] {
            child.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(child)
        }
        let width = card.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor, multiplier: 0.85)
        width.priority = .defaultHigh
        NSLayoutConstraint.activate([
            width,
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(lessThanOrEqualToConstant: 380),
            close.topAnchor.constraint(equalTo: card.topAnchor, constant: 4),
            close.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -4),
            close.widthAnchor.constraint(equalToConstant: 44),
            close.heightAnchor.constraint(equalToConstant: 44),
            message.topAnchor.constraint(equalTo: close.bottomAnchor, constant: 4),
            message.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            message.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            button.topAnchor.constraint(equalTo: message.bottomAnchor, constant: 24),
            button.leadingAnchor.constraint(equalTo: message.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: message.trailingAnchor),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            button.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24)
        ])
    }

    @objc private func closeTapped() { dismiss(animated: true) }
    @objc private func downloadTapped() {
        let action = download
        dismiss(animated: true) { action() }
    }
}
