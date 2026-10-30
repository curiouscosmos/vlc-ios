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
    var range: DiscourseClipRange { didSet { update() } }
    var cut: (() -> Void)?
    var seek: ((Double) -> Void)?
    private let timeline = DiscourseClipTimeline()
    private let startHandle = DiscourseClipHandle()
    private let endHandle = DiscourseClipHandle()
    private let selection = UIView()
    private let times = UILabel()
    private let summary = UILabel()
    private let cutButton = UIButton(type: .system)

    init(range: DiscourseClipRange) {
        self.range = range
        super.init(frame: .zero)
        backgroundColor = DiscourseColors.current.surfaceStart.withAlphaComponent(0.9)
        times.textColor = DiscourseColors.current.primaryText
        summary.textColor = DiscourseColors.current.primaryText
        layer.cornerRadius = 16
        layer.borderWidth = 1
        layer.borderColor = UIColor.separator.cgColor
        times.font = .preferredFont(forTextStyle: .caption1)
        times.adjustsFontForContentSizeCategory = true
        times.textAlignment = .center
        summary.font = .preferredFont(forTextStyle: .subheadline)
        summary.adjustsFontForContentSizeCategory = true
        summary.numberOfLines = 0
        timeline.minimumValue = 0
        timeline.maximumValue = Float(range.duration)
        timeline.tintColor = .secondaryLabel
        timeline.setThumbImage(UIImage(named: "sliderThumb"), for: .normal)
        timeline.accessibilityLabel = NSLocalizedString("PLAYBACK_POSITION", comment: "")
        timeline.addTarget(self, action: #selector(scrub), for: .valueChanged)
        selection.backgroundColor = DiscourseColors.current.accent
        selection.isUserInteractionEnabled = false
        [times, timeline, selection, startHandle, endHandle, summary, cutButton].forEach(addSubview)
        for (handle, key) in [(startHandle, NSLocalizedString("CLIP_START", comment: "")), (endHandle, NSLocalizedString("CLIP_END", comment: ""))] {
            handle.isAccessibilityElement = true
            handle.accessibilityTraits = .adjustable
            handle.accessibilityLabel = key
            let bar = UIView()
            bar.backgroundColor = .white
            bar.layer.cornerRadius = 5
            bar.frame = CGRect(x: 17, y: 9, width: 10, height: 26)
            bar.isUserInteractionEnabled = false
            handle.addSubview(bar)
            handle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(drag(_:))))
        }
        startHandle.adjust = { [weak self] delta in
            guard let self else { return }; self.range.moveStart(to: self.range.start + delta)
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
        update()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = max(1, bounds.height / 140)
        times.frame = CGRect(x: 12, y: 4, width: bounds.width - 24, height: 26 * scale)
        timeline.frame = CGRect(x: 22, y: 30 * scale, width: bounds.width - 44, height: 44)
        let track = timeline.convert(timeline.trackRect(forBounds: timeline.bounds), to: self)
        let startX = track.minX + track.width * range.start / range.duration
        let endX = track.minX + track.width * range.end / range.duration
        selection.frame = CGRect(x: startX, y: track.midY - 2, width: endX - startX, height: 4)
        startHandle.frame = CGRect(x: startX - 22, y: track.midY - 22, width: 44, height: 44)
        endHandle.frame = CGRect(x: endX - 22, y: track.midY - 22, width: 44, height: 44)
        let buttonWidth = min(bounds.width - 24, max(120, cutButton.intrinsicContentSize.width))
        summary.frame = CGRect(x: 12, y: 78 * scale, width: bounds.width - buttonWidth - 36, height: bounds.height - 82 * scale)
        cutButton.frame = CGRect(x: bounds.width - buttonWidth - 12, y: 80 * scale, width: buttonWidth, height: 44 * scale)
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
    }

    private func update() {
        times.text = "\(DiscourseClipRange.time(range.start))  —  \(DiscourseClipRange.time(range.end))"
        summary.text = String(format: NSLocalizedString("CLIP_SELECTED", comment: ""), DiscourseClipRange.time(range.end - range.start))
        startHandle.accessibilityValue = DiscourseClipRange.time(range.start)
        endHandle.accessibilityValue = DiscourseClipRange.time(range.end)
        setNeedsLayout()
    }

    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        let track = timeline.convert(timeline.trackRect(forBounds: timeline.bounds), to: self)
        let value = ((gesture.location(in: self).x - track.minX) / max(1, track.width) * range.duration).rounded()
        if gesture.view === startHandle { range.moveStart(to: value) } else { range.moveEnd(to: value) }
    }

    @objc private func scrub() { seek?(min(range.end, max(range.start, Double(timeline.value)))) }
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
