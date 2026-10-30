/*
 * Copyright (c) 2026 Sandalbar Enterprises, Inc.
 * Part of Rajneesh Discourse. GPLv2 or later; see COPYING.
 */
import AVFoundation

final class DiscourseClipExporter {
    private var generation = UUID()
    private var session: AVAssetExportSession?
    private var workingDirectory: URL?
    private(set) var outputURL: URL?
    static var directory: URL { FileManager.default.temporaryDirectory.appendingPathComponent("DiscourseClips", isDirectory: true) }

    static func cleanInterruptedExports() { try? FileManager.default.removeItem(at: directory) }

    func cancel() { generation = UUID(); session?.cancelExport(); clean() }
    func clean() {
        if let folder = workingDirectory { try? FileManager.default.removeItem(at: folder) }
        workingDirectory = nil
        outputURL = nil
    }

    func export(source: URL, sourceExtension: String? = nil, title: String, range: DiscourseClipRange, completion: @escaping (Result<URL, Error>) -> Void) {
        let token = UUID()
        generation = token
        let folder = Self.directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        workingDirectory = folder
        let fileExtension = (sourceExtension ?? source.pathExtension).lowercased().filter { $0.isLetter || $0.isNumber }
        let input = folder.appendingPathComponent("source").appendingPathExtension(fileExtension.isEmpty || fileExtension == "audio" ? "mp3" : String(fileExtension.prefix(12)))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // AVFoundation needs a recognizable extension; the download store deliberately uses .audio.
            do { try FileManager.default.linkItem(at: source, to: input) }
            catch { try FileManager.default.copyItem(at: source, to: input) }
        } catch {
            clean()
            DispatchQueue.main.async { [weak self] in
                guard self?.generation == token else { return }
                completion(.failure(error))
            }
            return
        }
        let asset = AVURLAsset(url: input)
        asset.loadValuesAsynchronously(forKeys: ["duration", "tracks"]) { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.generation == token else {
                    try? FileManager.default.removeItem(at: folder)
                    return
                }
                guard asset.statusOfValue(forKey: "duration", error: nil) == .loaded,
                      asset.statusOfValue(forKey: "tracks", error: nil) == .loaded else {
                    self.clean()
                    completion(.failure(NSError(domain: "DiscourseClip", code: 1))); return
                }
                let seconds = CMTimeGetSeconds(asset.duration)
                let end = min(range.end, seconds)
                guard seconds.isFinite, range.start >= 0, end - range.start >= 1,
                      !asset.tracks(withMediaType: .audio).isEmpty,
                      let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
                    self.clean()
                    completion(.failure(NSError(domain: "DiscourseClip", code: 1))); return
                }
                self.session = session
                let safeTitle = title.components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted).joined(separator: " ")
                let filename = String(safeTitle.prefix(100)) + " " + DiscourseClipRange.time(range.start).replacingOccurrences(of: ":", with: "-") + " to " + DiscourseClipRange.time(end).replacingOccurrences(of: ":", with: "-") + ".m4a"
                let url = folder.appendingPathComponent(filename)
                self.outputURL = url
                session.outputURL = url
                session.outputFileType = .m4a
                session.timeRange = CMTimeRange(start: CMTime(seconds: range.start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))
                session.exportAsynchronously {
                    DispatchQueue.main.async {
                        guard self.generation == token else {
                            try? FileManager.default.removeItem(at: folder)
                            return
                        }
                        if session.status == .completed { completion(.success(url)) }
                        else {
                            try? FileManager.default.removeItem(at: folder)
                            if self.generation == token { self.outputURL = nil }
                            completion(.failure(session.error ?? NSError(domain: "DiscourseClip", code: 2)))
                        }
                    }
                }
            }
        }
    }
}
