/*****************************************************************************
 * DiscourseDownloadManager.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * The active side of downloads: one background `URLSession` (AGENTS.md 6.6).
 * Tracks are queued three at a time, progress is reported through
 * `.discourseDownloadsDidChange` at most once per 2%, and finished files move
 * into `DiscourseDownloadStore`. A task carries `audioID|discourseID` in its
 * `taskDescription`, so a download that outlived the app is re-attached to its
 * track after relaunch (the background session keeps it running while the app
 * is suspended).
 *****************************************************************************/

import Foundation

/// What a track's download control and menu should show.
enum DiscourseDownloadState: Equatable {
    case missing
    case downloading(progress: Double)
    case downloaded
    case failed
}

@objc(DiscourseDownloadManager)
final class DiscourseDownloadManager: NSObject {
    static let shared = DiscourseDownloadManager()

    static let backgroundSessionIdentifier = "online.sandalbar.rajneesh-discourse.downloads"
    private static let maxConcurrentDownloads = 3
    /// Notify at most once per 2% so a fast download cannot flood the screens.
    private static let progressStep = 0.02

    private final class Job {
        let audioID: String
        let discourseID: String
        let url: URL
        var task: URLSessionDownloadTask?

        init(audioID: String, discourseID: String, url: URL) {
            self.audioID = audioID
            self.discourseID = discourseID
            self.url = url
        }
    }

    private let store: DiscourseDownloadStore
    private let notificationCenter: NotificationCenter
    private let queue = DispatchQueue(label: "online.sandalbar.rajneesh-discourse.downloads.manager")

    private var session: URLSession!
    /// taskIdentifier → job for the tasks this process knows about.
    private var taskInfo: [Int: Job] = [:]
    /// audioID → 0…1 for the active tasks.
    private var progress: [String: Double] = [:]
    /// audioID → discourseID for tracks whose last attempt failed (cleared by a
    /// retry or a removal).
    private var failures: [String: String] = [:]
    private var pending: [Job] = []
    /// Set by `handleEventsForBackgroundURLSession:completionHandler:`.
    private var backgroundCompletionHandler: (() -> Void)?

    init(store: DiscourseDownloadStore = .shared,
         notificationCenter: NotificationCenter = .default) {
        self.store = store
        self.notificationCenter = notificationCenter
        super.init()

        let configuration = URLSessionConfiguration.background(
            withIdentifier: Self.backgroundSessionIdentifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.httpMaximumConnectionsPerHost = Self.maxConcurrentDownloads
        configuration.allowsCellularAccess = true
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)

        attachExistingTasks()
    }

    // MARK: - Reading

    func state(for audioID: String) -> DiscourseDownloadState {
        let snapshot: (progress: Double?, failed: Bool) = queue.sync {
            (progress[audioID], failures[audioID] != nil)
        }
        if let fraction = snapshot.progress {
            return .downloading(progress: fraction)
        }
        if store.isDownloaded(audioID: audioID) {
            return .downloaded
        }
        return snapshot.failed ? .failed : .missing
    }

    func activeCount(forDiscourse discourseID: String) -> Int {
        return queue.sync {
            taskInfo.values.filter { $0.discourseID == discourseID }.count
                + pending.filter { $0.discourseID == discourseID }.count
        }
    }

    func hasActiveDownloads(forDiscourse discourseID: String) -> Bool {
        return activeCount(forDiscourse: discourseID) > 0
    }

    // MARK: - Writing

    func download(_ track: DiscourseAudio, discourseID: String? = nil) {
        let owner = discourseID ?? track.discourseID
        guard !owner.isEmpty,
              let url = track.audioURL else {
            return
        }
        enqueue(Job(audioID: track.id, discourseID: owner, url: url))
    }

    /// Queues every track of a discourse that is not already downloaded.
    func downloadAll(tracks: [DiscourseAudio], discourseID: String) {
        for track in tracks where !store.isDownloaded(audioID: track.id) {
            download(track, discourseID: discourseID)
        }
    }

    func cancel(audioID: String) {
        var task: URLSessionDownloadTask?
        var changed = false
        queue.sync {
            if let job = taskInfo.values.first(where: { $0.audioID == audioID }) {
                task = job.task
                changed = true
            }
            if pending.contains(where: { $0.audioID == audioID }) {
                pending.removeAll { $0.audioID == audioID }
                changed = true
            }
        }
        task?.cancel()
        if changed {
            postChange()
        }
    }

    func cancelAll(discourseID: String) {
        var tasks: [URLSessionDownloadTask] = []
        var changed = false
        queue.sync {
            tasks = taskInfo.values
                .filter { $0.discourseID == discourseID }
                .compactMap(\.task)
            if pending.contains(where: { $0.discourseID == discourseID }) {
                pending.removeAll { $0.discourseID == discourseID }
                changed = true
            }
        }
        guard !tasks.isEmpty || changed else {
            return
        }
        for task in tasks {
            task.cancel()
        }
        postChange()
    }

    /// Cancels an in-flight download and deletes any finished file.
    func remove(audioID: String) {
        cancel(audioID: audioID)
        store.remove(audioID: audioID)
        queue.sync {
            failures.removeValue(forKey: audioID)
        }
        postChange()
    }

    /// Cancels and deletes every download of one discourse.
    func removeAll(discourseID: String) {
        cancelAll(discourseID: discourseID)
        store.removeAll(forDiscourse: discourseID)
        queue.sync {
            failures = failures.filter { $0.value != discourseID }
        }
        postChange()
    }

    // MARK: - Background lifetime

    /// Called from `VLCAppDelegate` — `application:handleEventsForBackgroundURLSession:completionHandler:`.
    @objc(handleBackgroundEventsWithIdentifier:completionHandler:)
    static func handleBackgroundEvents(identifier: String,
                                       completionHandler: @escaping () -> Void) {
        guard identifier == backgroundSessionIdentifier else {
            DispatchQueue.main.async {
                completionHandler()
            }
            return
        }
        // Touching `shared` creates the session, which reconnects the delegate
        // to the downloads that were running while the app was suspended.
        shared.queue.sync {
            shared.backgroundCompletionHandler = completionHandler
        }
    }

    // MARK: - Internals

    private func enqueue(_ job: Job) {
        var started = false
        queue.sync {
            guard taskInfo.values.allSatisfy({ $0.audioID != job.audioID }),
                  !pending.contains(where: { $0.audioID == job.audioID }) else {
                return
            }
            if store.isDownloaded(audioID: job.audioID) {
                return
            }
            failures.removeValue(forKey: job.audioID)
            if taskInfo.count < Self.maxConcurrentDownloads {
                startTaskLocked(job)
                started = true
            } else {
                pending.append(job)
            }
        }
        if started {
            postChange()
        }
    }

    /// Must be called on `queue`.
    private func startTaskLocked(_ job: Job) {
        let task = session.downloadTask(with: job.url)
        task.taskDescription = Self.taskDescription(audioID: job.audioID,
                                                    discourseID: job.discourseID)
        job.task = task
        taskInfo[task.taskIdentifier] = job
        progress[job.audioID] = 0
        task.resume()
    }

    /// Must be called on `queue`.
    private func startNextLocked() {
        while taskInfo.count < Self.maxConcurrentDownloads, !pending.isEmpty {
            startTaskLocked(pending.removeFirst())
        }
    }

    private func finish(_ job: Job, taskIdentifier: Int, failed: Bool) {
        var completion: (() -> Void)?
        queue.sync {
            taskInfo.removeValue(forKey: taskIdentifier)
            progress.removeValue(forKey: job.audioID)
            if failed {
                failures[job.audioID] = job.discourseID
            }
            startNextLocked()
            // The system calls `urlSessionDidFinishEvents`, but if the last task
            // finished before it did (or the session was recreated), release the
            // snapshot here as well.
            if taskInfo.isEmpty, pending.isEmpty {
                completion = backgroundCompletionHandler
                backgroundCompletionHandler = nil
            }
        }
        postChange()
        if let completion {
            DispatchQueue.main.async(execute: completion)
        }
    }

    private func job(for task: URLSessionTask) -> Job? {
        if let known = queue.sync(execute: { taskInfo[task.taskIdentifier] }) {
            return known
        }
        // A task that survived a relaunch may deliver before `getAllTasks`
        // returns; its description is authoritative.
        return Self.job(from: task.taskDescription)
    }

    private func attachExistingTasks() {
        session.getAllTasks { [weak self] tasks in
            guard let self else {
                return
            }
            var changed = false
            self.queue.sync {
                for task in tasks {
                    guard let job = Self.job(from: task.taskDescription),
                          self.taskInfo[task.taskIdentifier] == nil else {
                        continue
                    }
                    job.task = task as? URLSessionDownloadTask
                    self.taskInfo[task.taskIdentifier] = job
                    let fraction = task.progress.fractionCompleted
                    self.progress[job.audioID] = fraction.isFinite ? fraction : 0
                    changed = true
                }
            }
            if changed {
                self.postChange()
            }
        }
    }

    private func postChange() {
        let center = notificationCenter
        if Thread.isMainThread {
            center.post(name: .discourseDownloadsDidChange, object: self)
        } else {
            DispatchQueue.main.async {
                center.post(name: .discourseDownloadsDidChange, object: self)
            }
        }
    }

    private static func taskDescription(audioID: String, discourseID: String) -> String {
        return "\(audioID)|\(discourseID)"
    }

    private static func job(from description: String?) -> Job? {
        guard let description else {
            return nil
        }
        let parts = description.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return nil
        }
        let audioID = String(parts[0])
        let discourseID = String(parts[1])
        guard !audioID.isEmpty, !discourseID.isEmpty else {
            return nil
        }
        // The URL is only needed to *start* a task; a reattached job moves the
        // file the system already downloaded, so a placeholder is enough.
        return Job(audioID: audioID,
                   discourseID: discourseID,
                   url: URL(fileURLWithPath: "/"))
    }
}

// MARK: - URLSessionDownloadDelegate

extension DiscourseDownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let job = job(for: downloadTask) else {
            return
        }
        do {
            try store.storeDownloadedFile(at: location,
                                          audioID: job.audioID,
                                          discourseID: job.discourseID)
            finish(job, taskIdentifier: downloadTask.taskIdentifier, failed: false)
        } catch {
            DiscourseDiagnostics.log("Could not store download for \(job.audioID): \(error)",
                                     context: "Downloads")
            finish(job, taskIdentifier: downloadTask.taskIdentifier, failed: true)
        }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0,
              let job = job(for: downloadTask) else {
            return
        }
        let fraction = min(1, max(0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        var changed = false
        queue.sync {
            let previous = progress[job.audioID] ?? 0
            if fraction >= 1 || fraction - previous >= Self.progressStep {
                progress[job.audioID] = fraction
                changed = true
            }
        }
        if changed {
            postChange()
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        let known = queue.sync { taskInfo[task.taskIdentifier] }
        if error == nil, known == nil {
            // Finished in `didFinishDownloadingTo`; the move already ran.
            return
        }
        guard let job = known ?? Self.job(from: task.taskDescription) else {
            return
        }
        if let error = error as NSError?,
           error.domain == NSURLErrorDomain,
           error.code == NSURLErrorCancelled {
            finish(job, taskIdentifier: task.taskIdentifier, failed: false)
            return
        }
        if error != nil {
            DiscourseDiagnostics.log("Download failed for \(job.audioID): \(String(describing: error))",
                                     level: .warning,
                                     context: "Downloads")
        }
        finish(job, taskIdentifier: task.taskIdentifier, failed: true)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        var completion: (() -> Void)?
        queue.sync {
            completion = backgroundCompletionHandler
            backgroundCompletionHandler = nil
        }
        if let completion {
            DispatchQueue.main.async(execute: completion)
        }
    }
}
