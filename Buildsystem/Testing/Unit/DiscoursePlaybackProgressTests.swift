/*****************************************************************************
 * DiscoursePlaybackProgressTests.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * The playback rules of AGENTS 6.3: 60 seconds of real playback before a play
 * qualifies, pauses and seeks excluded, a save every 30 seconds, completion at
 * the end, replay-from-start re-arming the play, and the resume fraction handed
 * to `VLCPlaybackService.startPosition`.
 *****************************************************************************/

import XCTest
@testable import VLC

final class DiscoursePlaybackProgressTests: XCTestCase {
    private var progress = DiscoursePlaybackProgress()

    override func setUp() {
        super.setUp()
        progress = DiscoursePlaybackProgress()
        progress.begin(audioID: "a1",
                       discourseID: "d1",
                       durationMilliseconds: 600_000,
                       startPositionMilliseconds: 0)
    }

    // MARK: - Qualification

    func testPlayQualifiesAfterSixtySecondsOfPlayback() {
        for second in 1...59 {
            let effects = tick(Double(second) * 1_000)
            XCTAssertFalse(effects.contains(qualify),
                           "a play must not qualify after \(second) s")
        }

        let effects = tick(60_000)
        XCTAssertTrue(effects.contains(qualify), "60 s of playback qualifies the play")
    }

    func testPausedAndBufferingTimeDoesNotCount() {
        for second in 1...30 {
            _ = tick(Double(second) * 1_000, isPlaying: true)
        }
        XCTAssertEqual(progress.session?.accumulatedMilliseconds, 30_000)

        // The position keeps advancing while the player is buffering, but that
        // is not playback time.
        for second in 31...60 {
            _ = tick(Double(second) * 1_000, isPlaying: false)
        }
        XCTAssertEqual(progress.session?.accumulatedMilliseconds, 30_000)
        XCTAssertFalse(progress.session?.qualified ?? true)
    }

    func testSeekJumpsDoNotCountAsPlayback() {
        _ = tick(1_000)
        _ = tick(200_000, durationMilliseconds: 600_000)
        XCTAssertEqual(progress.session?.accumulatedMilliseconds, 1_000,
                       "a large forward jump is a seek")

        _ = tick(201_000)
        XCTAssertEqual(progress.session?.accumulatedMilliseconds, 2_000)
    }

    func testStartingMidwayDoesNotCountTheResumeOffset() {
        progress.begin(audioID: "a1",
                       discourseID: "d1",
                       durationMilliseconds: 600_000,
                       startPositionMilliseconds: 100_000)

        _ = tick(101_000)
        XCTAssertEqual(progress.session?.accumulatedMilliseconds, 1_000)
    }

    func testDurationLearnedFromThePlayerReplacesTheStoredHint() {
        progress.begin(audioID: "a1",
                       discourseID: "d1",
                       durationMilliseconds: 0,
                       startPositionMilliseconds: 0)
        _ = tick(10_000, durationMilliseconds: 120_000)
        XCTAssertEqual(progress.session?.durationMilliseconds, 120_000)
    }

    // MARK: - Saves

    func testPositionIsSavedEveryThirtySecondsOfPlayback() {
        var saves: [(Double)] = []
        for second in 1...60 {
            let effects = tick(Double(second) * 1_000)
            saves.append(contentsOf: effects.compactMap { effect in
                guard case .savePosition(_, let position) = effect else { return nil }
                return position
            })
        }
        XCTAssertEqual(saves, [30_000, 60_000])
    }

    func testFlushSavesTheCurrentPosition() {
        _ = tick(5_000)
        _ = tick(7_000)
        XCTAssertEqual(progress.flush(), [.savePosition(audioID: "a1", positionMilliseconds: 7_000)])
    }

    func testFlushAfterCompletionDoesNotSave() {
        _ = tick(599_500)
        XCTAssertEqual(progress.flush(), [])
    }

    // MARK: - Completion

    func testCompletesAtTheEndAndStopsEmitting() {
        let effects = tick(599_500)
        XCTAssertTrue(effects.contains(.complete(audioID: "a1")))

        let again = tick(599_800)
        XCTAssertTrue(again.isEmpty, "a finished track is not completed twice")
    }

    func testReplayingFromTheStartArmsANewPlay() {
        _ = tick(599_500)
        XCTAssertTrue(progress.session?.finished ?? false)

        // Seek back to the start: the tracker clears the completed flag when it
        // begins the new session, and the rules restart the counters here.
        _ = tick(500)
        let effects = tick(1_500)
        XCTAssertEqual(progress.session?.accumulatedMilliseconds, 1_000)
        XCTAssertFalse(effects.contains(qualify))
    }

    // MARK: - Resume

    func testResumeFraction() {
        XCTAssertNil(DiscoursePlaybackResume.fraction(durationMilliseconds: 600_000,
                                                      positionMilliseconds: 500,
                                                      completed: false))
        XCTAssertNil(DiscoursePlaybackResume.fraction(durationMilliseconds: 600_000,
                                                      positionMilliseconds: 100_000,
                                                      completed: true))
        XCTAssertNil(DiscoursePlaybackResume.fraction(durationMilliseconds: 600_000,
                                                      positionMilliseconds: 596_000,
                                                      completed: false),
                     "never resume into the last seconds")
        XCTAssertNil(DiscoursePlaybackResume.fraction(durationMilliseconds: 0,
                                                      positionMilliseconds: 100_000,
                                                      completed: false))

        let fraction = DiscoursePlaybackResume.fraction(durationMilliseconds: 600_000,
                                                        positionMilliseconds: 300_000,
                                                        completed: false)
        XCTAssertEqual(fraction ?? 0, 0.5, accuracy: 0.0001)

        let clamped = DiscoursePlaybackResume.fraction(durationMilliseconds: 100_000,
                                                       positionMilliseconds: 99_500,
                                                       completed: false)
        XCTAssertNil(clamped, "the tail margin wins over clamping")

        let nearEndButValid = DiscoursePlaybackResume.fraction(durationMilliseconds: 600_000,
                                                               positionMilliseconds: 594_000,
                                                               completed: false)
        XCTAssertEqual(nearEndButValid ?? 0, 0.98, accuracy: 0.0001)
    }

    // MARK: - Registry

    func testRegistryKeepsTheMostRecentTracksAndDiscourses() {
        let registry = DiscourseTrackRegistry()
        let tracks = (0..<(DiscourseTrackRegistry.limit + 10)).map { track("a\($0)") }
        registry.register(tracks: tracks, discourse: discourse("d1"))

        XCTAssertNil(registry.track(id: "a0"), "the oldest entries are evicted")
        XCTAssertNotNil(registry.track(id: "a\(tracks.count - 1)"))
        XCTAssertEqual(registry.discourse(id: "d1")?.id, "d1")
    }

    func testRegistryReplacesExistingPayloads() {
        let registry = DiscourseTrackRegistry()
        registry.register(tracks: [track("a1")])
        registry.register(tracks: [track("a1", title: "Updated")])
        XCTAssertEqual(registry.track(id: "a1")?.title, "Updated")
    }

    // MARK: - Fixtures

    private var qualify: DiscoursePlaybackProgress.Effect {
        return .qualify(audioID: "a1", discourseID: "d1")
    }

    private func tick(_ position: Double,
                      durationMilliseconds: Double = 600_000,
                      isPlaying: Bool = true) -> [DiscoursePlaybackProgress.Effect] {
        return progress.tick(positionMilliseconds: position,
                             durationMilliseconds: durationMilliseconds,
                             isPlaying: isPlaying)
    }

    private func track(_ id: String, title: String = "Track") -> DiscourseAudio {
        DiscourseAudio(id: id,
                       discourseID: "d1",
                       discourseName: "Discourse",
                       title: title,
                       audioURLString: "https://osho.b-cdn.net/OSHO/\(id).mp3")
    }

    private func discourse(_ id: String) -> Discourse {
        Discourse(id: id, title: "Discourse \(id)")
    }
}
