/* Copyright (c) 2026 Sandalbar Enterprises, Inc. GPLv2 or later; see COPYING. */
import XCTest
import AVFoundation
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
