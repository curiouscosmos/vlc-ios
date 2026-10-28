/*****************************************************************************
 * DiscourseLikeActions.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * One place performs a like toggle and one place reports a failure, so the
 * catalogue, the detail screen, the search/Home rows and the audio player all
 * behave the same way: the store updates the heart immediately, the server
 * settles the count in the background, and a failure reverts the tap and shows
 * the spec's copy.
 *****************************************************************************/

import UIKit

@MainActor
enum DiscourseLikeActions {
    static func toggleDiscourse(_ discourse: Discourse,
                                from viewController: UIViewController?,
                                store: DiscourseLikesStore = .shared) {
        if !store.isLiked(.discourse(discourse.id)) { store.capture(discourse: discourse) }
        Task { @MainActor in
            do {
                try await store.toggleDiscourse(id: discourse.id,
                                                totalLikes: discourse.totalLikes)
            } catch {
                DiscourseDiagnostics.log("discourse like request failed",
                                         level: .warning,
                                         context: "Likes")
                presentFailure(from: viewController)
            }
        }
    }

    static func toggleAudio(_ track: DiscourseAudio,
                            from viewController: UIViewController?,
                            store: DiscourseLikesStore = .shared) {
        if !store.isLiked(.audio(track.id)) { store.capture(audio: track) }
        Task { @MainActor in
            do {
                try await store.toggleAudio(id: track.id,
                                            totalLikes: track.totalLikes)
            } catch {
                DiscourseDiagnostics.log("track like request failed",
                                         level: .warning,
                                         context: "Likes")
                presentFailure(from: viewController)
            }
        }
    }

    static func presentFailure(from viewController: UIViewController?) {
        guard let viewController,
              let top = topViewController(from: viewController),
              top.isViewLoaded,
              top.view.window != nil else {
            return
        }
        let alert = UIAlertController(title: nil,
                                      message: DiscourseErrorCopy.likeFailure,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("BUTTON_OK",
                                                              comment: "Acknowledge a message"),
                                      style: .default))
        top.present(alert, animated: true)
    }

    private static func topViewController(from viewController: UIViewController) -> UIViewController? {
        var top: UIViewController? = viewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
