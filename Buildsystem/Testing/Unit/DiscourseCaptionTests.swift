/* Copyright (c) 2026 Sandalbar Enterprises, Inc. GPLv2 or later; see COPYING. */
import XCTest
import UIKit
@testable import VLC

final class DiscourseCaptionTests: XCTestCase {
    private let source = "\u{FEFF}1\r\n00:00:11,000 --> 00:00:15,110\r\n<b>ओम नमः</b>\r\nश्री संभवे,\r\n\r\n2\r\n00:00:16,460 --> 00:00:18,290\r\nस्वात्मानंद\r\n"

    func testSRTUnicodeMultilineAndBoundaries() {
        let captions = DiscourseCaptions.parse(source)
        XCTAssertEqual(captions.count, 2)
        XCTAssertEqual(captions.first?.text, "ओम नमः\nश्री संभवे,")
        XCTAssertEqual(captions.first?.start, 11)
        XCTAssertEqual(captions.first?.end, 15.11)
        XCTAssertEqual(DiscourseCaptions.activeIndex(in: captions, at: 10.99), 0)
        XCTAssertEqual(DiscourseCaptions.activeIndex(in: captions, at: 11), 0)
        XCTAssertEqual(DiscourseCaptions.activeIndex(in: captions, at: 15.11), 0)
        XCTAssertEqual(DiscourseCaptions.activeIndex(in: captions, at: 16), 0)
        XCTAssertEqual(DiscourseCaptions.activeIndex(in: captions, at: 16.46), 1)
        XCTAssertEqual(DiscourseCaptions.activeIndex(in: captions, at: 18.29), 1)
        XCTAssertEqual(DiscourseCaptions.activeIndex(in: captions, at: 200), 1)
        XCTAssertEqual(DiscourseCaptions.activeIndex(in: captions, at: 12), 0)
        XCTAssertNil(DiscourseCaptions.activeIndex(in: captions, at: .nan))
        XCTAssertNil(DiscourseCaptions.activeIndex(in: [], at: 0))
    }

    func testMalformedCuesAreSkippedAndValidCuesSorted() {
        let captions = DiscourseCaptions.parse("""
        1
        00:01:00,000 --> 00:01:01,000
        Later

        2
        00:00:05,000 --> 00:00:03,000
        Reversed

        3
        00:99:00,000 --> 01:00:00,000
        Invalid

        4
        00:00:01,000 --> 00:00:02,000
        First

        5
        00:00:03,000 --> 00:00:04,000
        <b></b>
        """)
        XCTAssertEqual(captions.map(\.text), ["First", "Later"])
        XCTAssertTrue(DiscourseCaptions.parse("not captions").isEmpty)
    }

    func testMetadataDefaultsAndRoundTrip() throws {
        let decoder = JSONDecoder()
        let legacy = try decoder.decode(DiscourseAudio.self, from: Data(#"{"id":"a"}"#.utf8))
        XCTAssertFalse(legacy.hasCC)
        XCTAssertNil(legacy.captionURL)
        let audio = try decoder.decode(DiscourseAudio.self, from: Data(#"{"id":"a","has_cc":true,"cc_path":"Shiv Sutra/cc/Shiv_Sutra_01.srt"}"#.utf8))
        XCTAssertEqual(audio.captionURL?.absoluteString, "https://osho.b-cdn.net/OSHO/Shiv%20Sutra/cc/Shiv_Sutra_01.srt")
        XCTAssertEqual(try decoder.decode(DiscourseAudio.self, from: JSONEncoder().encode(audio)), audio)
        for value in [#"{"id":"a","has_cc":null,"cc_path":null}"#, #"{"id":"a","has_cc":"yes","cc_path":4}"#] {
            XCTAssertNil(try decoder.decode(DiscourseAudio.self, from: Data(value.utf8)).captionURL)
        }
        let invalid = DiscourseAudio(id: "a", discourseID: "d", discourseName: "", title: "", audioURLString: "", hasCC: true, ccPath: "http://example.com/a.srt")
        XCTAssertNil(invalid.captionURL)
    }

    func testLoaderFailureRetryCachingAndNoAPIKey() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CaptionURLProtocol.self]
        configuration.urlCache = URLCache(memoryCapacity: 1024 * 1024, diskCapacity: 0, diskPath: nil)
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); CaptionURLProtocol.handler = nil }
        let url = try XCTUnwrap(URL(string: "https://captions.example/test.srt"))
        let loader = DiscourseCaptionLoader(session: session)
        CaptionURLProtocol.handler = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "x-api-key"))
            return (503, Data())
        }
        do { _ = try await loader.load(url: url); XCTFail("HTTP failures must remain retryable") } catch { }
        let body = Data(source.utf8)
        CaptionURLProtocol.handler = { request in
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            return (200, body)
        }
        let loaded = try await loader.load(url: url, forceRefresh: true)
        XCTAssertEqual(loaded.count, 2)
        XCTAssertNotNil(configuration.urlCache?.cachedResponse(for: URLRequest(url: url)))
        let cancelled = Task { () throws -> [DiscourseCaption] in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await loader.load(url: url)
        }
        do { _ = try await cancelled.value; XCTFail("Cancelled requests must not return cached captions") } catch { }
    }

    @MainActor
    func testActiveBracketPersistsAndUsesPhraseBoundaries() throws {
        let editor = DiscourseClipEditor(range: DiscourseClipRange(duration: 200, position: 20))
        var starts: [Double] = []
        editor.previewPositionDidChange = { starts.append($0) }
        editor.selectPhrase(DiscourseCaption(start: 30, end: 35, text: "any word"))
        XCTAssertEqual(editor.range.start, 30)
        editor.selectPhrase(DiscourseCaption(start: 40, end: 45, text: "another word"))
        XCTAssertEqual(editor.range.start, 40)
        XCTAssertEqual(starts, [30, 40])
        let end = try XCTUnwrap(editor.subviews.first { $0.accessibilityIdentifier == "clipEndBracket" })
        XCTAssertTrue(end.accessibilityActivate())
        XCTAssertTrue(end.accessibilityTraits.contains(.selected))
        editor.selectPhrase(DiscourseCaption(start: 50, end: 55, text: "end"))
        editor.selectPhrase(DiscourseCaption(start: 60, end: 65, text: "new end"))
        XCTAssertEqual(editor.range.start, 40)
        XCTAssertEqual(editor.range.end, 65)
        XCTAssertEqual(starts, [30, 40, 45, 55])
        editor.selectPhrase(DiscourseCaption(start: 0, end: 5, text: "before start"))
        XCTAssertEqual(editor.range.end, 41)
        editor.selectEndpoint(.start)
        editor.selectPhrase(DiscourseCaption(start: 190, end: 220, text: "after end"))
        XCTAssertEqual(editor.range.start, 40)
        editor.selectEndpoint(.end)
        editor.selectPhrase(DiscourseCaption(start: 190, end: 220, text: "past track"))
        XCTAssertEqual(editor.range.end, 200)
    }

    @MainActor
    func testTranscriptDisplaysAllPhrasesAndReportsTaps() throws {
        let view = DiscourseCaptionView(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        let captions = DiscourseCaptions.parse(source)
        let transcript = try XCTUnwrap(view.subviews.compactMap { $0 as? UITextView }.first)
        if #available(iOS 16.0, *) {
            // Check before display, taps or accessibility geometry can cause implicit fallback.
            XCTAssertNil(transcript.textLayoutManager)
        }
        view.display(captions)
        XCTAssertEqual(transcript.text, "ओम नमः श्री संभवे, स्वात्मानंद")
        XCTAssertNil(transcript.accessibilityValue)
        XCTAssertNil(transcript.accessibilityAttributedValue)
        let elements = try XCTUnwrap(transcript.accessibilityElements as? [UIAccessibilityElement])
        XCTAssertEqual(elements.count, 2)
        var tapped: DiscourseCaption?
        view.phraseTapped = { tapped = $0 }
        XCTAssertTrue(elements[1].accessibilityActivate())
        XCTAssertEqual(tapped, captions[1])
        view.update(time: 11, range: nil)
        XCTAssertEqual(elements[0].accessibilityValue, "Currently playing")
        let color = transcript.textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        XCTAssertEqual(color, DiscourseColors.current.accent)
        view.update(time: 16, range: nil)
        XCTAssertEqual(elements[0].accessibilityValue, "Currently playing")
        view.update(time: 16.46, range: nil)
        XCTAssertNil(elements[0].accessibilityValue)
        XCTAssertEqual(elements[1].accessibilityValue, "Currently playing")
        view.update(time: 200, range: nil)
        XCTAssertEqual(elements[1].accessibilityValue, "Currently playing")
        view.update(time: 12, range: nil)
        XCTAssertEqual(elements[0].accessibilityValue, "Currently playing")
        transcript.delegate?.scrollViewWillBeginDragging?(transcript)
        let follow = try XCTUnwrap(view.subviews.compactMap { $0 as? UIButton }.first { $0.currentTitle == "Follow current phrase" })
        XCTAssertFalse(follow.isHidden)
        follow.sendActions(for: .touchUpInside)
        XCTAssertTrue(follow.isHidden)
        view.update(time: 16, range: DiscourseClipRange(duration: 200, position: 11))
        XCTAssertTrue(elements[0].accessibilityTraits.contains(.button))
        XCTAssertNotNil(elements[0].accessibilityHint)
        // The rendered paragraph changes, while source cues retain their SRT line breaks.
        XCTAssertEqual(view.captions[0].text, "ओम नमः\nश्री संभवे,")
        view.layoutIfNeeded()
        XCTAssertGreaterThan(elements[0].accessibilityFrame.width, 0)
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { context in
            view.layer.render(in: context.cgContext)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Continuous caption paragraph"; attachment.lifetime = .keepAlways; add(attachment)
        view.showLoading()
        XCTAssertTrue(view.captions.isEmpty)
        view.showFailure()
        let retry = try XCTUnwrap(view.subviews.compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "captionRetry" })
        XCTAssertFalse(retry.isHidden)
        var retries = 0
        view.retry = { retries += 1 }
        retry.sendActions(for: .touchUpInside)
        XCTAssertEqual(retries, 1)
    }
}

private final class CaptionURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler,
              let url = request.url else { return }
        let (status, data) = handler(request)
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .allowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
