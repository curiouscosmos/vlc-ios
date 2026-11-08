/* Copyright (c) 2026 Sandalbar Enterprises, Inc. GPLv2 or later; see COPYING. */
import AVFoundation
import UIKit
import Darwin

struct DiscourseClipExportRequest {
    let source: URL
    let sourceExtension: String?
    let title: String
    let range: DiscourseClipRange
    enum VideoRatio: CaseIterable { case original, mobile, desktop }
    var videoRatio: VideoRatio = .original
    var visual: URL?
    var noise = false
    var music: URL?
    var musicEnabled = false
    var musicVolume: Float = 0.5
    var musicLoops = true
    var captions: [DiscourseCaption]?
    var fadeIn = false
    var fadeOut = false
}

final class DiscourseClipExporter {
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var workingDirectory: URL?
    private(set) var outputURL: URL?
    static var directory: URL { FileManager.default.temporaryDirectory.appendingPathComponent("DiscourseClips", isDirectory: true) }
    static func cleanInterruptedExports() { try? FileManager.default.removeItem(at: directory) }
    static func error(_ key: String) -> Error {
        let message: String
        switch key {
        case "CLIP_MUSIC_MISSING": message = NSLocalizedString("CLIP_MUSIC_MISSING", comment: "")
        case "CLIP_NOISE_MISSING": message = NSLocalizedString("CLIP_NOISE_MISSING", comment: "")
        case "CLIP_SOURCE_SHORT": message = NSLocalizedString("CLIP_SOURCE_SHORT", comment: "")
        case "CLIP_VISUAL_FAILED": message = NSLocalizedString("CLIP_VISUAL_FAILED", comment: "")
        case "CLIP_CC_FAILED": message = NSLocalizedString("CLIP_CC_FAILED", comment: "")
        default: message = NSLocalizedString("CLIP_FAILED", comment: "")
        }
        return NSError(domain: "DiscourseClip", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    func cancel() { generation = UUID(); task?.cancel(); task = nil; clean() }
    func clean() {
        if let folder = workingDirectory { try? FileManager.default.removeItem(at: folder) }
        workingDirectory = nil
        outputURL = nil
    }

    // Retained for callers that only need unprocessed audio.
    func export(source: URL, sourceExtension: String? = nil, title: String, range: DiscourseClipRange,
                completion: @escaping (Result<URL, Error>) -> Void) {
        export(DiscourseClipExportRequest(source: source, sourceExtension: sourceExtension, title: title, range: range)) {
            completion($0.map { $0[0] })
        }
    }

    func export(_ request: DiscourseClipExportRequest, progress: @escaping (Double) -> Void = { _ in },
                completion: @escaping (Result<[URL], Error>) -> Void) {
        cancel()
        let token = generation
        let folder = Self.directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        workingDirectory = folder
        // Snapshot the mixer before yielding: removing/changing its selection cannot change this render.
        var request = request
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if request.musicEnabled {
                guard let music = request.music else { throw Self.error("CLIP_MUSIC_MISSING") }
                let copy = folder.appendingPathComponent("music").appendingPathExtension(music.pathExtension)
                do { try FileManager.default.copyItem(at: music, to: copy) }
                catch { throw Self.error("CLIP_MUSIC_MISSING") }
                request.music = copy
            }
        } catch {
            clean()
            DispatchQueue.main.async { [weak self] in
                guard self?.generation == token else { return }
                completion(.failure(error))
            }
            return
        }
        task = Task.detached(priority: .userInitiated) { [weak self] in
            let result: Result<[URL], Error>
            do { result = .success(try await Self.render(request, folder: folder, progress: progress)) }
            catch { result = .failure(error) }
            if Task.isCancelled { try? FileManager.default.removeItem(at: folder); return }
            await MainActor.run { [weak self] in
                guard let self, self.workingDirectory == folder else { return }
                if case .success(let urls) = result { self.outputURL = urls.first }
                else { self.clean() }
                completion(result)
            }
        }
    }

    private static func render(_ request: DiscourseClipExportRequest, folder: URL,
                               progress: @escaping (Double) -> Void) async throws -> [URL] {
        try Task.checkCancellation()
        let ext = (request.sourceExtension ?? request.source.pathExtension).lowercased().filter { $0.isLetter || $0.isNumber }
        let input = folder.appendingPathComponent("source").appendingPathExtension(ext.isEmpty || ext == "audio" ? "mp3" : String(ext.prefix(12)))
        do { try FileManager.default.linkItem(at: request.source, to: input) }
        catch { try FileManager.default.copyItem(at: request.source, to: input) }
        let start = request.range.start
        let end = request.range.end
        guard start.isFinite, end.isFinite, start >= 0, end - start >= 1 else { throw error("CLIP_FAILED") }
        let frames = Int64(((end - start) * 48000).rounded())
        let assetDuration = CMTimeGetSeconds(AVURLAsset(url: input).duration)
        guard assetDuration.isFinite, end <= assetDuration + 1 / 48000 else { throw error("CLIP_SOURCE_SHORT") }
        // Warm the sample-rate converter too; trim output rather than truncating its input.
        let preroll = min(start, 1)
        let decoder = try PCMReader(url: input, start: start - preroll, duration: nil)
        let noise = request.noise ? try Noise() : nil
        let skip = Int64((preroll * 48000).rounded()) + (request.noise ? 960 : 0)
        let music: PCMReader?
        if request.musicEnabled {
            guard let url = request.music else { throw error("CLIP_MUSIC_MISSING") }
            music = try PCMReader(url: url, start: 0, duration: nil)
        } else { music = nil }
        let spoolURL = folder.appendingPathComponent("render.caf")
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2) else { throw error("CLIP_FAILED") }
        var peak: Float = 1
        do {
            let spool = try AVAudioFile(forWriting: spoolURL, settings: format.settings)
            var consumed: Int64 = 0
            var written: Int64 = 0
            var drained = false
            var lastProgress = -1
            while written < frames {
                try Task.checkCancellation()
                var samples: [Float]
                if let block = try decoder.next() { samples = block }
                else if !drained {
                    // AVAssetReader's rate converter may withhold its final filter samples at EOF.
                    // The validated source covers the range; pad at most 128 converter-tail frames.
                    let tail = (request.noise ? 960 : 0) + 128
                    samples = [Float](repeating: 0, count: tail * 2)
                    drained = true
                }
                else { throw error("CLIP_SOURCE_SHORT") }
                try noise?.process(&samples)
                let blockFrames = Int64(samples.count / 2)
                let drop = Int(min(blockFrames, max(0, skip - consumed)))
                consumed += blockFrames
                let count = Int(min(Int64(samples.count / 2 - drop), frames - written))
                if count == 0 { continue }
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
                      let channels = buffer.floatChannelData else { throw error("CLIP_FAILED") }
                buffer.frameLength = AVAudioFrameCount(count)
                for index in 0..<count {
                    let bed = try music?.frame(loop: request.musicLoops) ?? (0, 0)
                    let left = samples[(drop + index) * 2] + bed.0 * request.musicVolume
                    let right = samples[(drop + index) * 2 + 1] + bed.1 * request.musicVolume
                    guard left.isFinite, right.isFinite else { throw error("CLIP_FAILED") }
                    peak = max(peak, abs(left), abs(right))
                    channels[0][index] = left
                    channels[1][index] = right
                }
                try spool.write(from: buffer)
                written += Int64(count)
                let fraction = Double(written) / Double(frames) * 0.45
                if Int(fraction * 100) != lastProgress {
                    lastProgress = Int(fraction * 100)
                    await MainActor.run { progress(fraction) }
                }
            }
        }
        let safe = request.title.components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted).joined(separator: " ")
        let basename = String(safe.prefix(100)) + " " + DiscourseClipRange.time(start).replacingOccurrences(of: ":", with: "-") + " to " + DiscourseClipRange.time(end).replacingOccurrences(of: ":", with: "-")
        let url = folder.appendingPathComponent(basename).appendingPathExtension(request.visual == nil ? "m4a" : "mp4")
        try await encode(spool: spoolURL, output: url, visual: request.visual, ratio: request.videoRatio, frames: frames, gain: 1 / peak, fadeIn: request.fadeIn, fadeOut: request.fadeOut, progress: progress)
        var urls = [url]
        if let captions = request.captions {
            let text = DiscourseCaptions.srt(captions, start: start, end: end)
            guard !text.isEmpty else { throw error("CLIP_CC_FAILED") }
            let srt = url.deletingPathExtension().appendingPathExtension("srt")
            try text.write(to: srt, atomically: true, encoding: .utf8)
            urls.append(srt)
        }
        try? FileManager.default.removeItem(at: spoolURL)
        return urls
    }

    static func fadeGain(frame: Int64, frames: Int64, fadeIn: Bool, fadeOut: Bool) -> Float {
        let length = min(96000, Double(frames) / (fadeIn && fadeOut ? 2 : 1))
        guard length > 0 else { return 1 }
        let start = fadeIn ? min(1, Double(frame) / length) : 1
        let end = fadeOut ? min(1, Double(max(0, frames - 1 - frame)) / length) : 1
        return Float(max(0, min(start, end)))
    }

    private static func encode(spool: URL, output: URL, visual: URL?, ratio: DiscourseClipExportRequest.VideoRatio, frames: Int64, gain: Float, fadeIn: Bool, fadeOut: Bool,
                               progress: @escaping (Double) -> Void) async throws {
        try Task.checkCancellation()
        let writer = try AVAssetWriter(outputURL: output, fileType: visual == nil ? .m4a : .mp4)
        defer { if writer.status == .writing { writer.cancelWriting() } }
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192000])
        writer.add(audio)
        let picture = try visual.map { try Visual(url: $0, ratio: ratio) }
        var video: AVAssetWriterInput?
        var adaptor: AVAssetWriterInputPixelBufferAdaptor?
        if let picture {
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: picture.width, AVVideoHeightKey: picture.height,
                AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]])
            writer.add(input)
            video = input
            adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: picture.width, kCVPixelBufferHeightKey as String: picture.height])
        }
        guard writer.startWriting() else { throw writer.error ?? error("CLIP_FAILED") }
        writer.startSession(atSourceTime: .zero)
        let file = try AVAudioFile(forReading: spool)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096),
              let channels = buffer.floatChannelData else { throw error("CLIP_FAILED") }
        var position: Int64 = 0
        var videoFrame: Int64 = 0
        var lastProgress = -1
        while position < frames || (picture != nil && videoFrame * 1600 < frames) {
            try Task.checkCancellation()
            // Interleave streams so neither writer input waits indefinitely on the other.
            if position < frames && audio.isReadyForMoreMediaData {
                try file.read(into: buffer, frameCount: AVAudioFrameCount(min(4096, frames - position)))
                guard buffer.frameLength > 0 else { throw error("CLIP_FAILED") }
                for channel in 0..<2 {
                    for index in 0..<Int(buffer.frameLength) {
                        channels[channel][index] *= gain * fadeGain(frame: position + Int64(index), frames: frames,
                                                                  fadeIn: fadeIn, fadeOut: fadeOut)
                    }
                }
                var description = buffer.format.streamDescription.pointee
                var format: CMAudioFormatDescription?
                guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &description, layoutSize: 0,
                    layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format) == noErr,
                    let format else { throw error("CLIP_FAILED") }
                var sample: CMSampleBuffer?
                guard CMAudioSampleBufferCreateWithPacketDescriptions(allocator: kCFAllocatorDefault, dataBuffer: nil,
                    dataReady: false, makeDataReadyCallback: nil, refcon: nil, formatDescription: format,
                    sampleCount: Int(buffer.frameLength), presentationTimeStamp: CMTime(value: position, timescale: 48000),
                    packetDescriptions: nil, sampleBufferOut: &sample) == noErr, let sample,
                    CMSampleBufferSetDataBufferFromAudioBufferList(sample, blockBufferAllocator: kCFAllocatorDefault,
                        blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0, bufferList: buffer.audioBufferList) == noErr,
                    CMSampleBufferSetDataReady(sample) == noErr, audio.append(sample) else { throw writer.error ?? error("CLIP_FAILED") }
                position += Int64(buffer.frameLength)
                if position == frames { audio.markAsFinished() }
            }
            if let picture, let video, let adaptor, videoFrame * 1600 < frames, video.isReadyForMoreMediaData {
                let pixel = try autoreleasepool { try picture.pixel(at: Double(videoFrame) / 30, pool: adaptor.pixelBufferPool) }
                guard adaptor.append(pixel, withPresentationTime: CMTime(value: videoFrame, timescale: 30)) else {
                    throw writer.error ?? error("CLIP_FAILED")
                }
                videoFrame += 1
                if videoFrame * 1600 >= frames { video.markAsFinished() }
            }
            if writer.status == .failed { throw writer.error ?? error("CLIP_FAILED") }
            let audioProgress = Double(position) / Double(frames)
            let visualProgress = picture == nil ? 1 : min(1, Double(videoFrame * 1600) / Double(frames))
            let fraction = 0.45 + min(audioProgress, visualProgress) * 0.55
            if Int(fraction * 100) != lastProgress {
                lastProgress = Int(fraction * 100)
                await MainActor.run { progress(fraction) }
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        writer.endSession(atSourceTime: CMTime(value: frames, timescale: 48000))
        await withCheckedContinuation { continuation in writer.finishWriting { continuation.resume() } }
        try Task.checkCancellation()
        guard writer.status == .completed else { throw writer.error ?? error("CLIP_FAILED") }
    }

    private final class PCMReader {
        let url: URL
        private var reader: AVAssetReader!
        private var output: AVAssetReaderTrackOutput!
        private var block: [Float] = []
        private var index = 0
        private var ended = false
        init(url: URL, start: Double, duration: Double?) throws {
            self.url = url
            try open(start: start, duration: duration)
        }
        private func open(start: Double, duration: Double?) throws {
            let asset = AVURLAsset(url: url)
            guard let track = asset.tracks(withMediaType: .audio).first else { throw error("CLIP_FAILED") }
            reader = try AVAssetReader(asset: asset)
            output = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false])
            reader.add(output)
            reader.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 48000),
                duration: duration.map { CMTime(seconds: $0, preferredTimescale: 48000) } ?? .positiveInfinity)
            guard reader.startReading() else { throw reader.error ?? error("CLIP_FAILED") }
        }
        func next() throws -> [Float]? {
            guard let sample = output.copyNextSampleBuffer() else {
                if reader.status == .failed { throw reader.error ?? error("CLIP_FAILED") }
                return nil
            }
            guard let data = CMSampleBufferGetDataBuffer(sample) else { throw error("CLIP_FAILED") }
            var values = [Float](repeating: 0, count: CMBlockBufferGetDataLength(data) / 4)
            guard !values.isEmpty else { return try next() }
            let result = values.withUnsafeMutableBytes { bytes -> OSStatus in
                guard let address = bytes.baseAddress else { return -1 }
                return CMBlockBufferCopyDataBytes(data, atOffset: 0, dataLength: bytes.count, destination: address)
            }
            guard result == noErr else { throw error("CLIP_FAILED") }
            return values
        }
        func frame(loop: Bool) throws -> (Float, Float) {
            if ended { return (0, 0) }
            if index >= block.count {
                block = try next() ?? []
                index = 0
                if block.isEmpty && loop { try open(start: 0, duration: nil); block = try next() ?? [] }
            }
            guard index + 1 < block.count else {
                if loop { throw error("CLIP_MUSIC_MISSING") }
                ended = true; return (0, 0)
            }
            defer { index += 2 }
            return (block[index], block[index + 1])
        }
        deinit { reader?.cancelReading() }
    }

    // RNNoise's exported C API keeps upstream VLCKit linkable without this capability.
    // Match Buildsystem/RNNoise/native/rnnoise_frame.h, including the startup crossfade.
    private final class Noise {
        typealias Create = @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
        typealias Process = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<Float>, UnsafePointer<Float>) -> Float
        typealias Destroy = @convention(c) (UnsafeMutableRawPointer) -> Void
        typealias FrameSize = @convention(c) () -> Int32
        private var states: [UnsafeMutableRawPointer] = []
        private let processFunction: Process
        private let destroy: Destroy
        private var input = [Float](repeating: 0, count: 960)
        private var wet = [Float](repeating: 0, count: 960)
        private var dry = [Float](repeating: 0, count: 1920)
        private var cursor = 0
        private var mix: Float = 0
        init() throws {
            let handle = UnsafeMutableRawPointer(bitPattern: -2)
            guard let create = dlsym(handle, "rnnoise_create"), let process = dlsym(handle, "rnnoise_process_frame"),
                  let destroy = dlsym(handle, "rnnoise_destroy"), let reset = dlsym(handle, "rnnoise_reset"),
                  let size = dlsym(handle, "rnnoise_get_frame_size"),
                  unsafeBitCast(size, to: FrameSize.self)() == 480 else { throw error("CLIP_NOISE_MISSING") }
            processFunction = unsafeBitCast(process, to: Process.self)
            self.destroy = unsafeBitCast(destroy, to: Destroy.self)
            for _ in 0..<2 {
                guard let state = unsafeBitCast(create, to: Create.self)(nil) else {
                    for state in states { self.destroy(state) }
                    states = []
                    throw error("CLIP_NOISE_MISSING")
                }
                states.append(state)
            }
            // Warm shared FFT tables, then reset without reallocating recurrent buffers.
            for state in states {
                input.withUnsafeBufferPointer { source in
                    wet.withUnsafeMutableBufferPointer { target in
                        if let source = source.baseAddress, let target = target.baseAddress {
                            _ = processFunction(state, target, source)
                        }
                    }
                }
                unsafeBitCast(reset, to: Destroy.self)(state)
            }
            wet = [Float](repeating: 0, count: 960)
        }
        func process(_ samples: inout [Float]) throws {
            for index in 0..<(samples.count / 2) {
                let frame = cursor % 480
                mix = min(1, mix + 1 / 480)
                for channel in 0..<2 {
                    let sample = index * 2 + channel
                    let delay = cursor * 2 + channel
                    let channelFrame = channel * 480 + frame
                    let original = samples[sample]
                    samples[sample] = dry[delay] * (1 - mix) + wet[channelFrame] * mix / 32768
                    dry[delay] = original
                    input[channelFrame] = original * 32768
                }
                cursor = (cursor + 1) % 960
                if cursor % 480 == 0 {
                    input.withUnsafeBufferPointer { source in
                        wet.withUnsafeMutableBufferPointer { target in
                            if let source = source.baseAddress, let target = target.baseAddress {
                                for channel in 0..<2 {
                                    _ = processFunction(states[channel], target + channel * 480, source + channel * 480)
                                }
                            }
                        }
                    }
                }
            }
        }
        deinit { for state in states { destroy(state) } }
    }

    private final class Visual {
        let width: Int
        let height: Int
        private let image: UIImage?
        private let generator: AVAssetImageGenerator?
        private let duration: Double
        private let ratio: DiscourseClipExportRequest.VideoRatio
        init(url: URL, ratio: DiscourseClipExportRequest.VideoRatio) throws {
            self.ratio = ratio
            image = UIImage(contentsOfFile: url.path)
            var size: CGSize
            if let image {
                size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
                generator = nil; duration = 0
            } else {
                let asset = AVURLAsset(url: url)
                guard let track = asset.tracks(withMediaType: .video).first else { throw error("CLIP_VISUAL_FAILED") }
                let rect = CGRect(origin: .zero, size: track.naturalSize).applying(track.preferredTransform)
                size = CGSize(width: abs(rect.width), height: abs(rect.height))
                duration = CMTimeGetSeconds(asset.duration)
                guard duration.isFinite, duration > 0 else { throw error("CLIP_VISUAL_FAILED") }
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.requestedTimeToleranceBefore = .zero
                generator.requestedTimeToleranceAfter = .zero
                // AVFoundation converts source colour into SDR Rec.709 before the 8-bit writer.
                let composition = AVMutableVideoComposition(propertiesOf: asset)
                composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
                composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
                composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
                generator.videoComposition = composition
                self.generator = generator
            }
            guard size.width > 0, size.height > 0 else { throw error("CLIP_VISUAL_FAILED") }
            let landscape = size.width >= size.height
            let scale = min(1, min((landscape ? 1920 : 1080) / size.width, (landscape ? 1080 : 1920) / size.height))
            if ratio == .original {
                width = max(2, Int(size.width * scale) / 2 * 2)
                height = max(2, Int(size.height * scale) / 2 * 2)
            } else {
                let unit = ratio == .mobile ? CGSize(width: 18, height: 32) : CGSize(width: 32, height: 18)
                let multiple = max(1, min(60, Int(min(size.width / unit.width, size.height / unit.height))))
                width = Int(unit.width) * multiple
                height = Int(unit.height) * multiple
            }
        }
        func pixel(at time: Double, pool: CVPixelBufferPool?) throws -> CVPixelBuffer {
            var pixel: CVPixelBuffer?
            guard let pool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixel) == kCVReturnSuccess, let pixel else {
                throw error("CLIP_VISUAL_FAILED")
            }
            let frame: UIImage
            if let image { frame = image }
            else if let generator {
                frame = UIImage(cgImage: try generator.copyCGImage(at: CMTime(seconds: time.truncatingRemainder(dividingBy: duration), preferredTimescale: 60000), actualTime: nil))
            } else { throw error("CLIP_VISUAL_FAILED") }
            CVPixelBufferLockBaseAddress(pixel, [])
            defer { CVPixelBufferUnlockBaseAddress(pixel, []) }
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: CVPixelBufferGetBaseAddress(pixel), width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixel), space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { throw error("CLIP_VISUAL_FAILED") }
            context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
            UIGraphicsPushContext(context)
            let natural = CGSize(width: frame.size.width * frame.scale, height: frame.size.height * frame.scale)
            let fit = ratio == .original
                ? min(1, min(CGFloat(width) / natural.width, CGFloat(height) / natural.height))
                : max(CGFloat(width) / natural.width, CGFloat(height) / natural.height)
            let size = CGSize(width: natural.width * fit, height: natural.height * fit)
            context.setFillColor(UIColor.black.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            frame.draw(in: CGRect(x: (CGFloat(width) - size.width) / 2, y: (CGFloat(height) - size.height) / 2,
                                  width: size.width, height: size.height))
            UIGraphicsPopContext()
            return pixel
        }
    }
}
