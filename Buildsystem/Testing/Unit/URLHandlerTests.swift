/*****************************************************************************
 * URLHandlerTests.swift
 * VLC for iOS
 *****************************************************************************
 * Copyright (c) 2018 VideoLAN. All rights reserved.
 * $Id$
 *
 * Authors: Carola Nitz <caro # videolan.org>
 *
 * Refer to the COPYING file of the official project for license.
 *****************************************************************************/

import XCTest
@testable import VLC

class URLHandlerTests: XCTestCase {

    func testGoogleSignInIsNotRegistered() {
        XCTAssertFalse(URLHandlers.handlers.contains { String(describing: type(of: $0)).contains("Google") })
        let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        let schemes = urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        XCTAssertFalse(schemes.contains { $0.hasPrefix("com.googleusercontent.apps") })
    }

    func testOnlyLocalFilesAreHandled() throws {
        XCTAssertEqual(URLHandlers.handlers.count, 1)
        let handler = try XCTUnwrap(URLHandlers.handlers.first)
        XCTAssertTrue(handler.canHandleOpen(url: URL(fileURLWithPath: "/tmp/discourse.mp3"), options: [:]))
        XCTAssertFalse(handler.canHandleOpen(url: URL(fileURLWithPath: "/tmp/readme.txt"), options: [:]))

        for value in ["vlc://example.com/audio.mp3", "vlc-x-callback://x-callback-url/stream?url=https://example.com/audio.mp3",
                      "https://example.com/audio.mp3", "ftp://example.com/audio.mp3", "feed://example.com/feed.xml",
                      "db-a60fc6qj9zdg7bw://callback"] {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertFalse(handler.canHandleOpen(url: url, options: [:]), value)
            XCTAssertFalse(handler.performOpen(url: url, options: [:]), value)
        }
    }

    func testLegacyURLSchemesAreNotRegistered() {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        XCTAssertTrue(schemes.isEmpty)
    }

    func testRetiredNetworkScreensAreAbsent() {
        for name in ["VLCHTTPUploaderController", "VLCServerListViewController", "VLCOnAirViewController",
                     "VLCRadioListViewController", "VLCCloudServicesTableViewController",
                     "VLCDonationViewController", "VLCFirstStepsViewController"] {
            XCTAssertNil(NSClassFromString(name), name)
        }
    }
    
}
