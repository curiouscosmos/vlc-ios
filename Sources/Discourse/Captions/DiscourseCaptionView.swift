/* Copyright (c) 2026 Sandalbar Enterprises, Inc. GPLv2 or later; see COPYING. */
import UIKit

private final class DiscourseCaptionText: UITextView {
    var userScrolled: (() -> Void)?
    private var phrases: [Any] = []
    override var accessibilityElements: [Any]? {
        get { phrases }
        set { phrases = newValue ?? [] }
    }
    override func accessibilityElementCount() -> Int { phrases.count }
    override func accessibilityElement(at index: Int) -> Any? {
        phrases.indices.contains(index) ? phrases[index] : nil
    }
    override func index(ofAccessibilityElement element: Any) -> Int {
        guard let element = element as? UIAccessibilityElement else { return NSNotFound }
        return phrases.firstIndex { ($0 as? UIAccessibilityElement) === element } ?? NSNotFound
    }
    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        userScrolled?()
        return super.accessibilityScroll(direction)
    }
}

private final class DiscourseCaptionElement: UIAccessibilityElement {
    weak var transcript: UITextView?
    var range = NSRange(location: 0, length: 0)
    var activate: (() -> Void)?
    override var accessibilityFrame: CGRect {
        get {
            guard let transcript else { return .zero }
            let glyphs = transcript.layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = transcript.layoutManager.boundingRect(forGlyphRange: glyphs, in: transcript.textContainer)
            rect.origin.x += transcript.textContainerInset.left
            rect.origin.y += transcript.textContainerInset.top
            return UIAccessibility.convertToScreenCoordinates(rect, in: transcript)
        }
        set { }
    }
    override func accessibilityActivate() -> Bool { activate?(); return activate != nil }
}

final class DiscourseCaptionView: UIView, UITextViewDelegate {
    var phraseTapped: ((DiscourseCaption) -> Void)?
    var retry: (() -> Void)?
    private(set) var captions: [DiscourseCaption] = []
    private let transcript = DiscourseCaptionText(frame: .zero, textContainer: nil)
    private var phraseRanges: [NSRange] = []
    private var phraseElements: [DiscourseCaptionElement] = []
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
        transcript.userScrolled = { [weak self] in self?.stopFollowing() }
        transcript.delegate = self
        transcript.backgroundColor = .clear
        transcript.isEditable = false
        transcript.isSelectable = false
        transcript.isAccessibilityElement = false
        transcript.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        transcript.accessibilityIdentifier = "discourseTranscript"
        transcript.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(transcriptTapped(_:))))
        message.font = .preferredFont(forTextStyle: .body)
        message.adjustsFontForContentSizeCategory = true
        message.numberOfLines = 0
        message.textAlignment = .center
        retryButton.setTitle(NSLocalizedString("CC_RETRY", comment: "Retry captions"), for: .normal)
        retryButton.accessibilityIdentifier = "captionRetry"
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        followButton.setTitle(NSLocalizedString("CC_FOLLOW", comment: "Follow current caption"), for: .normal)
        followButton.addTarget(self, action: #selector(followTapped), for: .touchUpInside)
        for child in [transcript, message, retryButton, followButton] {
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
        }
        NSLayoutConstraint.activate([
            transcript.leadingAnchor.constraint(equalTo: leadingAnchor), transcript.trailingAnchor.constraint(equalTo: trailingAnchor),
            transcript.topAnchor.constraint(equalTo: topAnchor), transcript.bottomAnchor.constraint(equalTo: followButton.topAnchor),
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
        rebuildTranscript()
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
        activeIndex = captions.isEmpty ? nil : 0
        message.isHidden = true
        retryButton.isHidden = true
        rebuildTranscript()
    }

    func update(time: Double, range: DiscourseClipRange?) {
        let next = DiscourseCaptions.activeIndex(in: captions, at: time)
        let positionChanged = next != activeIndex
        let rangeChanged = clipRange?.start != range?.start || clipRange?.end != range?.end
        clipRange = range
        guard positionChanged || rangeChanged else { return }
        let previous = activeIndex
        activeIndex = next
        transcript.textStorage.beginEditing()
        if rangeChanged {
            for index in captions.indices { stylePhrase(at: index) }
        } else {
            if let previous { stylePhrase(at: previous) }
            if let activeIndex { stylePhrase(at: activeIndex) }
        }
        transcript.textStorage.endEditing()
        if following && positionChanged { scrollToActive() }
    }

    func applyTheme() {
        backgroundColor = DiscourseColors.current.surfaceStart
        message.textColor = DiscourseColors.current.primaryText
        retryButton.tintColor = DiscourseColors.current.accent
        followButton.tintColor = DiscourseColors.current.accent
        rebuildTranscript()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            rebuildTranscript()
        }
    }

    private func rebuildTranscript() {
        let text = NSMutableAttributedString(string: "")
        phraseRanges = []
        phraseElements = []
        for (index, phrase) in captions.enumerated() {
            if index > 0 { text.append(NSAttributedString(string: " ")) }
            let value = phrase.text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
            let range = NSRange(location: text.length, length: (value as NSString).length)
            phraseRanges.append(range)
            text.append(NSAttributedString(string: value))
            let element = DiscourseCaptionElement(accessibilityContainer: transcript)
            element.isAccessibilityElement = true
            element.transcript = transcript
            element.range = range
            element.accessibilityIdentifier = "captionPhrase_\(index)"
            element.accessibilityLabel = value
            element.activate = { [weak self] in self?.selectPhrase(at: index) }
            phraseElements.append(element)
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 6
        text.addAttributes([.font: UIFont.preferredFont(forTextStyle: .title2, compatibleWith: traitCollection),
                            .foregroundColor: DiscourseColors.current.primaryText.withAlphaComponent(0.65),
                            .paragraphStyle: paragraph], range: NSRange(location: 0, length: text.length))
        transcript.attributedText = text
        transcript.accessibilityElements = phraseElements
        for index in captions.indices { stylePhrase(at: index) }
    }

    private func stylePhrase(at index: Int) {
        let phrase = captions[index]
        let selected = clipRange.map { phrase.start < $0.end && phrase.end > $0.start } ?? false
        transcript.textStorage.addAttributes([
            .foregroundColor: index == activeIndex ? DiscourseColors.current.accent : DiscourseColors.current.primaryText.withAlphaComponent(0.65),
            .backgroundColor: selected ? DiscourseColors.current.accent.withAlphaComponent(0.15) : UIColor.clear
        ], range: phraseRanges[index])
        let element = phraseElements[index]
        element.accessibilityTraits = clipRange == nil ? .staticText : .button
        element.accessibilityValue = index == activeIndex ? NSLocalizedString("CC_CURRENT", comment: "Current phrase") : nil
        element.accessibilityHint = clipRange == nil ? nil : NSLocalizedString("CC_SELECT_HINT", comment: "Caption clipping hint")
    }

    private func selectPhrase(at index: Int) {
        if clipRange != nil { stopFollowing() }
        phraseTapped?(captions[index])
    }

    @objc private func transcriptTapped(_ gesture: UITapGestureRecognizer) {
        var point = gesture.location(in: transcript)
        point.x -= transcript.textContainerInset.left
        point.y -= transcript.textContainerInset.top
        let layout = transcript.layoutManager
        let glyph = layout.glyphIndex(for: point, in: transcript.textContainer)
        guard glyph < layout.numberOfGlyphs,
              layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: transcript.textContainer).contains(point) else { return }
        let character = layout.characterIndexForGlyph(at: glyph)
        if let index = phraseRanges.firstIndex(where: { NSLocationInRange(character, $0) }) { selectPhrase(at: index) }
    }
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { stopFollowing() }
    private func stopFollowing() {
        following = false
        followButton.isHidden = captions.isEmpty
    }
    private func scrollToActive() {
        guard window != nil, let activeIndex, !transcript.isDragging, !transcript.isDecelerating else { return }
        transcript.scrollRangeToVisible(phraseRanges[activeIndex])
    }
    @objc private func retryTapped() { retry?() }
    @objc private func followTapped() { following = true; followButton.isHidden = true; scrollToActive() }
}
