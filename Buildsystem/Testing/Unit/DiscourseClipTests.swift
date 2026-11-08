/* Copyright (c) 2026 Sandalbar Enterprises, Inc. GPLv2 or later; see COPYING. */
import XCTest
import AVFoundation
import UIKit
import Darwin
import ImageIO
@testable import VLC

final class DiscourseClipTests: XCTestCase {
    @MainActor
    func testExportProgressShowsAudioOrVideoAndCanCancel() throws {
        let originalTheme = PresentationTheme.current
        defer { PresentationTheme.current = originalTheme }
        for (isVideo, largeText) in [(false, false), (true, false), (false, true)] {
            PresentationTheme.current = largeText ? .brightTheme : .darkTheme
            let controller = DiscourseClipProgressController(isVideo: isVideo)
            if #available(iOS 17.0, *) {
                controller.traitOverrides.preferredContentSizeCategory = largeText ? .accessibilityExtraExtraExtraLarge : .large
            }
            var cancelled = false
            controller.onCancel = { cancelled = true }
            controller.loadViewIfNeeded()
            controller.view.frame = CGRect(x: 0, y: 0, width: largeText ? 320 : 390, height: largeText ? 568 : 844)
            controller.view.layoutIfNeeded()
            func find(_ id: String, in view: UIView) -> UIView? {
                if view.accessibilityIdentifier == id { return view }
                return view.subviews.compactMap { find(id, in: $0) }.first
            }
            XCTAssertEqual(controller.modalPresentationStyle, .fullScreen)
            let heading = try XCTUnwrap(find("clipExportTitle", in: controller.view) as? UILabel)
            XCTAssertEqual(heading.text, isVideo ? "Creating Video Clip" : "Creating Audio Clip")
            let percentage = try XCTUnwrap(find("clipExportPercentage", in: controller.view) as? UILabel)
            controller.update(progress: 0.45)
            XCTAssertEqual(percentage.text, "45%")
            let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { context in
                controller.view.layer.render(in: context.cgContext)
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(largeText ? "clip-progress-large-text.png" : isVideo ? "clip-progress-video.png" : "clip-progress-audio.png")
            try image.pngData()?.write(to: url)
            print("Clip progress preview: \(url.path)")
            controller.update(progress: 2)
            XCTAssertEqual(percentage.text, "100%")
            controller.update(progress: .nan)
            XCTAssertEqual(percentage.text, "0%")
            let cancel = try XCTUnwrap(find("clipExportCancel", in: controller.view) as? UIButton)
            XCTAssertGreaterThanOrEqual(cancel.bounds.height, 44)
            let scroll = try XCTUnwrap(controller.view.subviews.first as? UIScrollView)
            scroll.scrollRectToVisible(cancel.convert(cancel.bounds, to: scroll), animated: false)
            XCTAssertTrue(scroll.bounds.contains(cancel.convert(cancel.bounds, to: scroll)),
                          "Cancel must remain reachable at accessibility text sizes")
            cancel.sendActions(for: .touchUpInside)
            XCTAssertTrue(cancelled)
        }
    }

    @MainActor
    func testDrawerCaptionsAreOptionalAndResetEachSession() throws {
        for (hasCC, path) in [(false, "https://example.com/a.srt"), (true, "https://example.com/a.srt"), (true, "http://invalid.example/a.srt")] {
            let track = DiscourseAudio(id: "a", discourseID: "d", discourseName: "", title: "Track", audioURLString: "",
                                       hasCC: hasCC, ccPath: path)
            func drawer() -> DiscourseClipSaveController {
                let controller = DiscourseClipSaveController(track: track, range: DiscourseClipRange(duration: 3, position: 0))
                controller.loadViewIfNeeded()
                return controller
            }
            let controller = drawer()
            func toggle(_ controller: DiscourseClipSaveController, section: Int, row: Int) throws -> UISwitch {
                let cell = controller.tableView(controller.tableView, cellForRowAt: IndexPath(row: row, section: section))
                return try XCTUnwrap(cell.accessoryView as? UISwitch)
            }
            let captions = try toggle(controller, section: 1, row: 2)
            XCTAssertEqual(captions.isEnabled, track.captionURL != nil)
            XCTAssertFalse(captions.isOn)
            if track.captionURL != nil {
                captions.isOn = true; captions.sendActions(for: .valueChanged)
                XCTAssertTrue(try toggle(controller, section: 1, row: 2).isOn)
                XCTAssertFalse(try toggle(drawer(), section: 1, row: 2).isOn)
            }
            for row in 0..<2 {
                let fade = try toggle(controller, section: 2, row: row)
                XCTAssertTrue(fade.isOn)
                fade.isOn = false; fade.sendActions(for: .valueChanged)
                XCTAssertFalse(try toggle(controller, section: 2, row: row).isOn)
                XCTAssertTrue(try toggle(drawer(), section: 2, row: row).isOn)
            }
            let noise = try toggle(controller, section: 1, row: 0)
            XCTAssertEqual(noise.isOn, PlaybackService.sharedInstance().noiseReductionEnabled)
            XCTAssertEqual(noise.isEnabled, PlaybackService.sharedInstance().noiseReductionAvailable)
            let mixer = DiscourseAudioMixer.shared
            let original = mixer.isEnabled
            defer { mixer.setEnabled(original) }
            mixer.setEnabled(!original)
            NotificationCenter.default.post(name: .discourseMixerDidChange, object: mixer)
            let music = try toggle(controller, section: 1, row: 1)
            XCTAssertEqual(music.isOn, !original)
            XCTAssertEqual(music.isEnabled, mixer.selectedURL != nil)
            if mixer.selectedURL == nil {
                let cell = controller.tableView(controller.tableView, cellForRowAt: IndexPath(row: 1, section: 1))
                XCTAssertEqual(cell.detailTextLabel?.text, "Add music in Mixer first")
            }
            for (row, title) in ["Share clip link", "Download clip audio", "Create video from clip"].enumerated() {
                let cell = controller.tableView(controller.tableView, cellForRowAt: IndexPath(row: row, section: 3))
                XCTAssertEqual(cell.contentView.subviews.compactMap { $0 as? UIButton }.first?.configuration?.title, title)
            }
        }
    }

    @MainActor
    func testDrawerLayoutsAtNarrowAndAccessibilitySizes() throws {
        let original = PresentationTheme.current
        defer { PresentationTheme.current = original }
        for (name, theme, category) in [("dark", PresentationTheme.darkTheme, UIContentSizeCategory.large),
                                         ("light", .brightTheme, .large),
                                         ("accessible", .darkTheme, .accessibilityExtraExtraExtraLarge)] {
            PresentationTheme.current = theme
            let track = DiscourseAudio(id: "a", discourseID: "d", discourseName: "", title: "A long discourse title that wraps on a narrow screen", audioURLString: "")
            let drawer = DiscourseClipSaveController(track: track, range: DiscourseClipRange(duration: 120, position: 10))
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.rootViewController = drawer
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            drawer.loadViewIfNeeded()
            if #available(iOS 17.0, *) {
                drawer.traitOverrides.preferredContentSizeCategory = category
                XCTAssertEqual(drawer.traitCollection.preferredContentSizeCategory, category)
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            drawer.view.frame = CGRect(x: 0, y: 0, width: 320, height: 568)
            drawer.view.layoutIfNeeded()
            drawer.tableView.reloadData(); drawer.tableView.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: drawer.view.bounds).image { context in
                drawer.view.layer.render(in: context.cgContext)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Export drawer \(name)"; attachment.lifetime = .keepAlways; add(attachment)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("clip-drawer-\(name).png")
            try image.pngData()?.write(to: url)
            print("Clip drawer preview: \(url.path)")
            let last = IndexPath(row: 2, section: 3)
            drawer.tableView.scrollToRow(at: last, at: .bottom, animated: false)
            drawer.tableView.layoutIfNeeded()
            XCTAssertTrue(drawer.tableView.indexPathsForVisibleRows?.contains(last) == true)
            let actions = UIGraphicsImageRenderer(bounds: drawer.view.bounds).image { context in
                drawer.view.layer.render(in: context.cgContext)
            }
            try actions.pngData()?.write(to: url.deletingLastPathComponent().appendingPathComponent("clip-drawer-\(name)-actions.png"))
            for cell in drawer.tableView.visibleCells {
                XCTAssertGreaterThanOrEqual(cell.bounds.height, 44)
                if let button = cell.contentView.subviews.compactMap({ $0 as? UIButton }).first {
                    XCTAssertLessThanOrEqual(button.bounds.height, drawer.view.safeAreaLayoutGuide.layoutFrame.height,
                                             "An action must fit the narrow viewport even at accessibility sizes")
                }
                if let toggle = cell.accessoryView {
                    XCTAssertLessThanOrEqual(cell.textLabel?.frame.maxX ?? 0, toggle.frame.minX)
                }
            }
        }
    }

    func testCaptionSidecarClipsBoundariesAndPreservesHindi() {
        let captions = [DiscourseCaption(start: 0, end: 1, text: "outside"),
                        DiscourseCaption(start: 1, end: 2.125, text: "ध्यान\nऔर प्रेम"),
                        DiscourseCaption(start: 3, end: 5, text: "end"),
                        DiscourseCaption(start: 4.5, end: 6, text: "outside")]
        XCTAssertEqual(DiscourseCaptions.srt(captions, start: 1.5, end: 4.5),
                       "1\n00:00:00,000 --> 00:00:00,625\nध्यान\nऔर प्रेम\n\n2\n00:00:01,500 --> 00:00:03,000\nend\n")
        XCTAssertEqual(DiscourseCaptions.srt(captions, start: 7, end: 8), "")
        XCTAssertEqual(DiscourseCaptions.srt(captions, start: .nan, end: 8), "")
    }

    func testProcessedExportMusicLoopPeakProtectionAndSidecar() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
        func tone(_ name: String, seconds: Double, amplitude: Float) throws -> URL {
            let url = folder.appendingPathComponent(name + ".wav")
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(seconds * 48000)))
            buffer.frameLength = buffer.frameCapacity
            let channels = try XCTUnwrap(buffer.floatChannelData)
            for index in 0..<Int(buffer.frameLength) {
                for channel in 0..<2 { channels[channel][index] = sin(Float(index) * 0.1) * amplitude }
            }
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
            return url
        }
        let source = try tone("speech", seconds: 3, amplitude: 0.8)
        let music = try tone("music", seconds: 0.5, amplitude: 0.8)
        let noiseOptions = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "rnnoise_reset") == nil ? [false] : [false, true]
        for (loops, noise) in noiseOptions.flatMap({ noise in [false, true].map { ($0, noise) } }) {
            let exporter = DiscourseClipExporter()
            defer { exporter.clean() }
            let captions = [DiscourseCaption(start: 0, end: 3, text: "ध्यान")]
            var request = DiscourseClipExportRequest(source: source, sourceExtension: "wav", title: "Mixed",
                range: DiscourseClipRange(duration: 2, position: 0), noise: noise, music: music, musicEnabled: true,
                musicVolume: 0.5, musicLoops: loops, captions: captions)
            let done = expectation(description: "Mixed export")
            exporter.export(request) { result in
                do {
                    let urls = try result.get()
                    XCTAssertEqual(urls.count, 2)
                    XCTAssertEqual(urls[0].deletingPathExtension(), urls[1].deletingPathExtension())
                    XCTAssertEqual(CMTimeGetSeconds(AVURLAsset(url: urls[0]).duration), 2, accuracy: 0.03)
                    XCTAssertTrue(try String(contentsOf: urls[1], encoding: .utf8).contains("ध्यान"))
                    let audio = try AVAudioFile(forReading: urls[0])
                    XCTAssertEqual(audio.processingFormat.sampleRate, 48000)
                    XCTAssertEqual(audio.processingFormat.channelCount, 2)
                    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(audio.length)))
                    try audio.read(into: buffer)
                    let channel = try XCTUnwrap(buffer.floatChannelData)[0]
                    let peak = (0..<Int(buffer.frameLength)).map { abs(channel[$0]) }.max() ?? 0
                    XCTAssertLessThan(peak, 1.08, "Allow AAC reconstruction overshoot")
                    XCTAssertGreaterThan(peak, noise ? 0.1 : 0.7)
                    if !noise {
                        let tailStart = Int(buffer.frameLength) / 2
                        let energy = (tailStart..<Int(buffer.frameLength)).reduce(Float(0)) { $0 + channel[$1] * channel[$1] }
                        let rms = sqrt(energy / Float(Int(buffer.frameLength) - tailStart))
                        XCTAssertEqual(rms, loops ? 0.707 : 0.471, accuracy: 0.06,
                                       "Music volume and loop setting must preserve the shared gain")
                    }
                } catch { XCTFail("Export failed: \(error)") }
                done.fulfill()
            }
            // The export owns a copy of this file before returning.
            request.musicVolume = 0
            wait(for: [done], timeout: 30)
        }
    }

    func testExportFadesInAudioAndVideoWithBackgroundMusic() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("tone.wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 288000))
        buffer.frameLength = buffer.frameCapacity
        let data = try XCTUnwrap(buffer.floatChannelData)
        for index in 0..<Int(buffer.frameLength) {
            for channel in 0..<2 { data[channel][index] = sin(Float(index) * Float.pi / 24) * 0.4 }
        }
        try AVAudioFile(forWriting: source, settings: format.settings).write(from: buffer)
        let image = folder.appendingPathComponent("photo.png")
        let picture = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { _ in
            UIColor.red.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        try picture.pngData()?.write(to: image)
        for duration in [1.0, 6.0] {
            for (fadeIn, fadeOut) in [(false, false), (true, false), (false, true), (true, true)] {
                for video in [false, true] {
                    let exporter = DiscourseClipExporter()
                    defer { exporter.clean() }
                    let done = expectation(description: "Faded soundtrack")
                    let request = DiscourseClipExportRequest(source: source, sourceExtension: "wav", title: "Fade",
                        range: DiscourseClipRange(duration: duration, position: 0), visual: video ? image : nil,
                        music: source, musicEnabled: true, musicVolume: 1, fadeIn: fadeIn, fadeOut: fadeOut)
                    exporter.export(request) { result in
                        do {
                            let url = try XCTUnwrap(try result.get().first)
                            XCTAssertEqual(CMTimeGetSeconds(AVURLAsset(url: url).duration), duration, accuracy: 0.035)
                            let audio = try AVAudioFile(forReading: url)
                            let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(audio.length)))
                            try audio.read(into: pcm)
                            let channel = try XCTUnwrap(pcm.floatChannelData)[0]
                            let count = Int(pcm.frameLength)
                            let ramp: [Float] = duration == 6 ? [0.06, 0.75, 1, 1, 1]
                                : fadeIn && fadeOut ? [0.04, 0.5, 1, 1, 1] : [0.02, 0.25, 0.5, 0.75, 0.98]
                            for (index, fraction) in [0.02, 0.25, 0.5, 0.75, 0.98].enumerated() {
                                let center = min(count - 481, max(480, Int(fraction * Double(count))))
                                let rms = sqrt((center-240..<center+240).reduce(Float(0)) { $0 + channel[$1] * channel[$1] } / 480)
                                let expected = 0.8 / sqrt(Float(2)) * min(fadeIn ? ramp[index] : 1, fadeOut ? ramp[4 - index] : 1)
                                XCTAssertEqual(rms, expected, accuracy: 0.035, "\(video) \(duration) \(fadeIn) \(fadeOut) at \(fraction)")
                            }
                        } catch { XCTFail("Fade export failed: \(error)") }
                        done.fulfill()
                    }
                    wait(for: [done], timeout: 30)
                }
            }
        }
        XCTAssertEqual(DiscourseClipExporter.fadeGain(frame: 0, frames: 48000, fadeIn: true, fadeOut: true), 0)
        XCTAssertEqual(DiscourseClipExporter.fadeGain(frame: 47999, frames: 48000, fadeIn: true, fadeOut: true), 0)
        XCTAssertEqual(DiscourseClipExporter.fadeGain(frame: 24000, frames: 48000, fadeIn: true, fadeOut: true), 1, accuracy: 0.0001)
    }

    func testNoiseWithoutMusicRetainsFractionalRange() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000 * 3))
        buffer.frameLength = buffer.frameCapacity
        let channels = try XCTUnwrap(buffer.floatChannelData)
        for channel in 0..<2 {
            for index in 0..<Int(buffer.frameLength) { channels[channel][index] = sin(Float(index) * 0.1) * 0.2 }
        }
        do { let file = try AVAudioFile(forWriting: url, settings: format.settings); try file.write(from: buffer) }
        var range = DiscourseClipRange(duration: 3, position: 0.375)
        range.moveEnd(to: 2.125)
        let exporter = DiscourseClipExporter()
        defer { exporter.clean() }
        let available = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "rnnoise_reset") != nil
        let done = expectation(description: "Noise only")
        exporter.export(DiscourseClipExportRequest(source: url, sourceExtension: "wav", title: "Noise", range: range, noise: true)) { result in
            switch result {
            case .success(let urls):
                XCTAssertTrue(available)
                XCTAssertEqual(CMTimeGetSeconds(AVURLAsset(url: urls[0]).duration), 1.75, accuracy: 0.025)
            case .failure(let error): if available { XCTFail("Noise rendering failed: \(error)") }
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 30)
    }

    func testPhotoVideoLoopTrimAndDiscardedSoundtrack() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let imageURL = folder.appendingPathComponent("portrait.png")
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 40), format: {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; return format
        }())
        let image = renderer.image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 24, height: 40))
        }
        try XCTUnwrap(image.pngData()).write(to: imageURL)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000 * 3))
        buffer.frameLength = buffer.frameCapacity
        let channels = try XCTUnwrap(buffer.floatChannelData)
        for channel in 0..<2 { for index in 0..<Int(buffer.frameLength) { channels[channel][index] = sin(Float(index) * 0.1) * 0.3 } }
        let source = folder.appendingPathComponent("silence.wav")
        do { let file = try AVAudioFile(forWriting: source, settings: format.settings); try file.write(from: buffer) }
        func export(_ visual: URL, duration: Double, name: String, size: CGSize = CGSize(width: 24, height: 40)) throws -> URL {
            let exporter = DiscourseClipExporter()
            defer { exporter.clean() }
            let copy = folder.appendingPathComponent(name + ".mp4")
            let done = expectation(description: name)
            var failure: Error?
            let request = DiscourseClipExportRequest(source: source, sourceExtension: "wav", title: name,
                range: DiscourseClipRange(duration: duration, position: 0), visual: visual)
            exporter.export(request) { result in
                do { try FileManager.default.copyItem(at: result.get()[0], to: copy) }
                catch { failure = error }
                done.fulfill()
            }
            wait(for: [done], timeout: 30)
            if let failure { throw failure }
            let asset = AVURLAsset(url: copy)
            XCTAssertEqual(CMTimeGetSeconds(asset.duration), duration, accuracy: 0.025)
            let video = try XCTUnwrap(asset.tracks(withMediaType: .video).first)
            XCTAssertEqual(video.naturalSize, size)
            XCTAssertEqual(video.nominalFrameRate, 30, accuracy: 0.1)
            XCTAssertEqual(asset.tracks(withMediaType: .audio).count, 1)
            if name != "photo" {
                let audio = try AVAudioFile(forReading: copy)
                let decoded = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(audio.length)))
                try audio.read(into: decoded)
                let channel = try XCTUnwrap(decoded.floatChannelData)[0]
                XCTAssertLessThan((0..<Int(decoded.frameLength)).map { abs(channel[$0]) }.max() ?? 0, 0.001,
                                  "The chosen video's original soundtrack must be discarded")
            }
            return copy
        }
        let short = try export(imageURL, duration: 1, name: "photo")
        for channel in 0..<2 { for index in 0..<Int(buffer.frameLength) { channels[channel][index] = 0 } }
        do { let file = try AVAudioFile(forWriting: source, settings: format.settings); try file.write(from: buffer) }
        let long = try export(short, duration: 2, name: "looped")
        _ = try export(long, duration: 1, name: "trimmed")
        let rotated = folder.appendingPathComponent("rotated.jpg")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(rotated as CFURL, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(image.cgImage), [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        _ = try export(rotated, duration: 1, name: "rotated", size: CGSize(width: 40, height: 24))
    }

    func testMissingEnabledMusicFailsExplicitly() {
        let exporter = DiscourseClipExporter()
        let done = expectation(description: "Missing effect rejected")
        let request = DiscourseClipExportRequest(source: URL(fileURLWithPath: "/missing"), sourceExtension: nil,
            title: "Missing", range: DiscourseClipRange(duration: 2, position: 0), musicEnabled: true)
        exporter.export(request) { result in
            if case .success = result { XCTFail("Enabled music cannot be silently omitted") }
            XCTAssertNil(exporter.outputURL)
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
    }

    func testInitialRangeAndTrackEnd() {
        XCTAssertEqual(DiscourseClipRange(duration: 2000, position: 20).end, 620)
        XCTAssertEqual(DiscourseClipRange(duration: 200, position: 20).end, 200)
        let nearEnd = DiscourseClipRange(duration: 200, position: 200)
        XCTAssertEqual(nearEnd.start, 199)
        XCTAssertEqual(nearEnd.end, 200)
        XCTAssertEqual(DiscourseClipRange(duration: 20, position: 0).end, 20)
    }

    func testHandlesCannotCrossOrEscapeTrack() {
        var range = DiscourseClipRange(duration: 200, position: 20)
        range.moveEnd(to: 80)
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
    func testPlayheadLabelPreservesSecondsAcrossSliderRounding() throws {
        let editor = DiscourseClipEditor(range: DiscourseClipRange(duration: 5869.44, position: 0))
        let label = try XCTUnwrap(editor.subviews.compactMap { $0 as? UILabel }.first { $0.accessibilityIdentifier == "clipPreviewTime" })
        for second in 1900...2000 {
            editor.setPosition(Double(second))
            XCTAssertEqual(label.text, DiscourseClipRange.time(Double(second)), "Exact second \(second) must survive slider display")
        }
    }

    @MainActor
    func testEndpointButtonsAndPreviewCallbacks() throws {
        let editor = DiscourseClipEditor(range: DiscourseClipRange(duration: 200, position: 20))
        editor.range.moveEnd(to: 80)
        let buttons = editor.subviews.compactMap { $0 as? UIButton }
        func button(_ key: String) throws -> UIButton {
            try XCTUnwrap(buttons.first { $0.accessibilityIdentifier == key })
        }
        var starts: [Double] = []
        editor.previewPositionDidChange = { starts.append($0) }
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
        XCTAssertEqual(starts, [19, 20, 69, 70])
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
        let playhead = try XCTUnwrap(editor.subviews.compactMap { $0 as? UILabel }.first { $0.accessibilityIdentifier == "clipPreviewTime" })
        XCTAssertEqual(playhead.text, "0:38")
        editor.range.moveEnd(to: 43)
        endMinus.sendActions(for: .touchUpInside)
        XCTAssertEqual(starts.last, 38, "Short selections clamp end preview to the start bracket")
        XCTAssertEqual(playhead.text, "0:38")
        editor.range.moveEnd(to: 100)
        endMinus.sendActions(for: .touchUpInside)
        XCTAssertEqual(starts.last, 89)
        XCTAssertEqual(playhead.text, "1:29")
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

    @MainActor
    func testClipPlayerKeepsTransportInsideSafeArea() {
        for size in [CGSize(width: 393, height: 852), CGSize(width: 375, height: 667)] {
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            let host = UIViewController()
            host.additionalSafeAreaInsets = size.height > 700
                ? UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
                : UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)
            window.rootViewController = host
            window.isHidden = false
            defer { window.isHidden = true }
            let player = AudioPlayerView(frame: window.bounds)
            player.translatesAutoresizingMaskIntoConstraints = false
            host.view.addSubview(player)
            NSLayoutConstraint.activate([
                player.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
                player.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
                player.topAnchor.constraint(equalTo: host.view.topAnchor),
                player.bottomAnchor.constraint(equalTo: host.view.bottomAnchor),
                player.navigationBarView.heightAnchor.constraint(equalToConstant: 44)
            ])
            player.updateLabels(title: "Es Dhammo Sanantano 001", artist: "Osho",
                                album: "Es Dhammo Sanantano 001", isQueueHidden: true)
            player.shouldEnableSeekButtons(true)
            player.setClipEditing(true)
            let editor = DiscourseClipEditor(range: DiscourseClipRange(duration: 5869, position: 689))
            editor.range.moveEnd(to: 1485)
            editor.setPosition(711)
            editor.translatesAutoresizingMaskIntoConstraints = false
            player.progressionView.addSubview(editor)
            NSLayoutConstraint.activate([
                editor.leadingAnchor.constraint(equalTo: player.progressionView.leadingAnchor, constant: 12),
                editor.trailingAnchor.constraint(equalTo: player.progressionView.trailingAnchor, constant: -12),
                editor.topAnchor.constraint(equalTo: player.progressionView.topAnchor),
                editor.bottomAnchor.constraint(equalTo: player.progressionView.bottomAnchor)
            ])
            for _ in 0..<3 { window.layoutIfNeeded(); player.setNeedsLayout() }
            window.layoutIfNeeded()
            XCTAssertLessThanOrEqual(player.controlsStackView.frame.maxY,
                                     player.safeAreaLayoutGuide.layoutFrame.maxY,
                                     "Transport clipped at \(size)")
            XCTAssertGreaterThanOrEqual(player.controlsStackView.frame.minY, player.progressionView.frame.maxY)
            let image = UIGraphicsImageRenderer(bounds: player.bounds).image { context in
                player.layer.render(in: context.cgContext)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "clip-full-player-\(Int(size.height))"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testPreviewSeeksOnceDespiteOptimisticAndStaleVLCTimestamps() {
        var preview = DiscourseClipPreview()
        preview.requestStart(at: 46)
        XCTAssertNil(preview.seekTarget(position: 92, isPlaying: false, isInteracting: false))
        XCTAssertNil(preview.seekTarget(position: 92, isPlaying: true, isInteracting: false))
        XCTAssertEqual(preview.seekTarget(position: 92.5, isPlaying: true, isInteracting: false), 46)
        // Reproduce the simulator trace: VLC first echoes the requested time,
        // then reports an earlier timestamp. Neither report may re-arm a seek.
        for position in [46.0, 14, 14.5, 15, 45, 46, 47, 60] {
            XCTAssertNil(preview.seekTarget(position: position, isPlaying: true, isInteracting: false))
        }
        XCTAssertNil(preview.pendingStart)
        preview.requestStart(at: 46)
        XCTAssertNil(preview.seekTarget(position: 60, isPlaying: true, isInteracting: false))
        XCTAssertEqual(preview.seekTarget(position: 60.5, isPlaying: true, isInteracting: false), 46)
    }

    func testPreviewWaitsForResumeAndDraggingBeforeOneShotSeek() {
        var preview = DiscourseClipPreview()
        preview.requestStart(at: 20)
        XCTAssertNil(preview.seekTarget(position: 0, isPlaying: true, isInteracting: false))
        XCTAssertNil(preview.seekTarget(position: 0, isPlaying: true, isInteracting: false))
        XCTAssertNil(preview.seekTarget(position: 1, isPlaying: true, isInteracting: true))
        preview.requestStart(at: 30)
        XCTAssertNil(preview.seekTarget(position: 1, isPlaying: true, isInteracting: false))
        XCTAssertEqual(preview.seekTarget(position: 1.5, isPlaying: true, isInteracting: false), 30)
        XCTAssertNil(preview.seekTarget(position: 2, isPlaying: true, isInteracting: false))
    }

    func testCancellationInvalidatesPendingWork() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: source) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000 * 4))
        buffer.frameLength = buffer.frameCapacity
        let channels = try XCTUnwrap(buffer.floatChannelData)
        for channel in 0..<2 { for index in 0..<Int(buffer.frameLength) { channels[channel][index] = 0 } }
        do { let file = try AVAudioFile(forWriting: source, settings: format.settings); try file.write(from: buffer) }
        let exporter = DiscourseClipExporter()
        let done = expectation(description: "Cancelled render does not deliver")
        done.isInverted = true
        let started = expectation(description: "Rendering began")
        var cancelled = false
        let request = DiscourseClipExportRequest(source: source, sourceExtension: "wav", title: "Cancel",
            range: DiscourseClipRange(duration: 4, position: 0))
        exporter.export(request, progress: { _ in
            if !cancelled { cancelled = true; exporter.cancel(); started.fulfill() }
        }) { _ in done.fulfill() }
        wait(for: [started], timeout: 10)
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
        range.moveEnd(to: 4)
        let tail = expectation(description: "Resampled EOF exported")
        exporter.export(source: source, sourceExtension: "wav", title: "EOF", range: range) { result in
            do {
                let url = try result.get()
                XCTAssertEqual(CMTimeGetSeconds(AVURLAsset(url: url).duration), 3, accuracy: 0.025)
            } catch { XCTFail("EOF export failed: \(error)") }
            tail.fulfill()
        }
        wait(for: [tail], timeout: 20)
    }
}
