/*****************************************************************************
 * DiscourseLaunchScreenTests.swift
 * Rajneesh Discourse
 *****************************************************************************
 * The launch screen is a static storyboard, so a missing asset would only show
 * up as a blank splash. This keeps the branded launch icon wired: the storyboard
 * must resolve it (name + asset catalog) and give the image view a real image.
 *****************************************************************************/

import XCTest
@testable import VLC

final class DiscourseLaunchScreenTests: XCTestCase {
    func testLaunchStoryboardUsesTheBrandedIcon() throws {
        let storyboard = UIStoryboard(name: "Launch Screen", bundle: .main)
        let controller = try XCTUnwrap(storyboard.instantiateInitialViewController())
        controller.loadViewIfNeeded()

        let imageViews = controller.view.subviews.compactMap { $0 as? UIImageView }
        let image = try XCTUnwrap(imageViews.first?.image, "no launch image")
        print("LAUNCH_IMAGE_SIZE \(image.size)")
        XCTAssertGreaterThan(image.size.width, 0)
    }
}
