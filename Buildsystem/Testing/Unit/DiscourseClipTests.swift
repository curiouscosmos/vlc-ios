/* Copyright (c) 2026 Sandalbar Enterprises, Inc. GPLv2 or later; see COPYING. */
import XCTest
import AVFoundation
import UIKit
@testable import VLC

final class DiscourseClipTests: XCTestCase {
    func testInitialRangeAndTrackEnd() {
        XCTAssertEqual(DiscourseClipRange(duration: 200, position: 20).end, 80)
        let nearEnd = DiscourseClipRange(duration: 200, position: 200)
        XCTAssertEqual(nearEnd.start, 199)
        XCTAssertEqual(nearEnd.end, 200)
        XCTAssertEqual(DiscourseClipRange(duration: 20, position: 0).end, 20)
    }

    func testHandlesCannotCrossOrEscapeTrack() {
        var range = DiscourseClipRange(duration: 200, position: 20)
        range.moveStart(to: 150)
        XCTAssertEqual(range.start, 79)
        range.moveEnd(to: 0)
        XCTAssertEqual(range.end, 80)
        range.moveStart(to: -10)
        range.moveEnd(to: 1000)
        XCTAssertEqual(range.start, 0)
        XCTAssertEqual(range.end, 200)
        range.moveStart(to: .nan)
        XCTAssertEqual(range.start, 0)
    }

    @MainActor
    func testEndpointButtonsAndPreviewCallbacks() throws {
        let editor = DiscourseClipEditor(range: DiscourseClipRange(duration: 200, position: 20))
        let buttons = editor.subviews.compactMap { $0 as? UIButton }
        func button(_ key: String) throws -> UIButton {
            try XCTUnwrap(buttons.first { $0.accessibilityIdentifier == key })
        }
        var starts: [Double] = []
        editor.startDidChange = { starts.append($0) }
        let startMinus = try button("CLIP_START_DECREASE")
        let startPlus = try button("CLIP_START_INCREASE")
        let endMinus = try button("CLIP_END_DECREASE")
        let endPlus = try button("CLIP_END_INCREASE")
        startMinus.sendActions(for: .touchUpInside)
        XCTAssertEqual(editor.range.start, 19)
        XCTAssertEqual(editor.range.end - editor.range.start, 61)
        startPlus.sendActions(for: .touchUpInside)
        XCTAssertEqual(editor.range.start, 20)
        endMinus.sendActions(for: .touchUpInside)
        XCTAssertEqual(editor.range.end, 79)
        endPlus.sendActions(for: .touchUpInside)
        XCTAssertEqual(editor.range.end, 80)
        XCTAssertEqual(starts, [19, 20])
        XCTAssertTrue(editor.subviews.compactMap { $0 as? UILabel }.contains { $0.text == "Selected: 1:00" })

        editor.range.moveStart(to: 0)
        editor.range.moveEnd(to: 1)
        XCTAssertFalse(startMinus.isEnabled)
        XCTAssertFalse(startPlus.isEnabled)
        XCTAssertFalse(endMinus.isEnabled)
        XCTAssertTrue(endPlus.isEnabled)
        editor.range.moveEnd(to: 200)
        XCTAssertFalse(endPlus.isEnabled)
        // A bracket drag uses the same range mutation; the next tap keeps its position.
        editor.range.moveStart(to: 37)
        startPlus.sendActions(for: .touchUpInside)
        XCTAssertEqual(editor.range.start, 38)
        XCTAssertEqual(starts.last, 38)
    }

    @MainActor
    func testPanelLayoutsAndPlayhead() {
        let originalTheme = PresentationTheme.current
        defer { PresentationTheme.current = originalTheme }
        for (name, width, category) in [("narrow", CGFloat(280), UIContentSizeCategory.large),
                                         ("large-text", CGFloat(353), .accessibilityExtraExtraExtraLarge)] {
            let traits = UITraitCollection(preferredContentSizeCategory: category)
            traits.performAsCurrent {
                PresentationTheme.current = name == "narrow" ? .brightTheme : .darkTheme
                let editor = DiscourseClipEditor(range: DiscourseClipRange(duration: 5400, position: 1200))
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 800))
                let host = UIViewController()
                window.rootViewController = host
                window.isHidden = false
                host.view.addSubview(editor)
                if #available(iOS 17.0, *) { host.traitOverrides.preferredContentSizeCategory = category }
                window.layoutIfNeeded()
                defer { window.isHidden = true }
                editor.range.moveEnd(to: 3600)
                editor.frame = CGRect(x: 0, y: 0, width: width, height: DiscourseClipEditor.preferredHeight(for: traits))
                editor.setPosition(1230)
                editor.layoutIfNeeded()
                let labels = editor.subviews.compactMap { $0 as? UILabel }
                XCTAssertTrue(labels.contains { $0.text == "20:30" })
                XCTAssertTrue(labels.contains { $0.text == "00:00" })
                XCTAssertTrue(labels.contains { $0.text == "1:30:00" })
                for button in editor.subviews.compactMap({ $0 as? UIButton }) {
                    XCTAssertTrue(editor.bounds.contains(button.frame))
                    XCTAssertGreaterThanOrEqual(button.frame.height, 44)
                }
                let image = UIGraphicsImageRenderer(bounds: editor.bounds).image { context in
                    editor.layer.render(in: context.cgContext)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "clip-panel-" + name
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    func testCancellationInvalidatesPendingWork() {
        let exporter = DiscourseClipExporter()
        let done = expectation(description: "Cancelled load does not deliver")
        done.isInverted = true
        exporter.export(source: URL(fileURLWithPath: "/missing/clip-source.wav"), title: "Missing",
                        range: DiscourseClipRange(duration: 4, position: 0)) { _ in done.fulfill() }
        exporter.cancel()
        wait(for: [done], timeout: 0.2)
        XCTAssertNil(exporter.outputURL)
    }

    func testMissingSourceFailsWithoutLeavingOutput() {
        let exporter = DiscourseClipExporter()
        let done = expectation(description: "Missing source rejected")
        exporter.export(source: URL(fileURLWithPath: "/missing/clip-source.wav"), title: "Missing",
                        range: DiscourseClipRange(duration: 4, position: 0)) { result in
            if case .success = result { XCTFail("Missing audio should fail") }
            XCTAssertNil(exporter.outputURL)
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
    }

    func testExportsSelectedAudioDuration() throws {
        let wav = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        let source = wav.deletingPathExtension().appendingPathExtension("audio")
        defer {
            try? FileManager.default.removeItem(at: wav)
            try? FileManager.default.removeItem(at: source)
        }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100 * 4))
        buffer.frameLength = buffer.frameCapacity
        if let samples = buffer.floatChannelData?[0] {
            for index in 0..<Int(buffer.frameLength) { samples[index] = Float(sin(Double(index) * 0.05)) * 0.1 }
        }
        do {
            let file = try AVAudioFile(forWriting: wav, settings: format.settings)
            try file.write(from: buffer)
        }
        try FileManager.default.moveItem(at: wav, to: source)
        let exporter = DiscourseClipExporter()
        defer { exporter.clean() }
        var range = DiscourseClipRange(duration: 4, position: 1)
        range.moveEnd(to: 3)
        let done = expectation(description: "Audio exported")
        exporter.export(source: source, sourceExtension: "wav", title: "Talk / sample", range: range) { result in
            switch result {
            case .success(let url):
                XCTAssertEqual(url.pathExtension, "m4a")
                XCTAssertEqual(CMTimeGetSeconds(AVURLAsset(url: url).duration), 2, accuracy: 0.15)
            case .failure(let error): XCTFail("Export failed: \(error)")
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 20)
        let output = try XCTUnwrap(exporter.outputURL)
        exporter.clean()
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
}
