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

    func testVLCHandler() {
        let handler = VLCCallbackURLHandler()
        let transformURLString = { handler.transformVLCURL(URL(string: $0)!) }
        XCTAssertEqual(transformURLString("vlc://http//test"), URL(string: "http://test")!, "strip the custom scheme and re-add the colon")
        XCTAssertEqual(transformURLString("vlc://http://test"), URL(string: "http://test")!, "just strip the custom scheme")
        XCTAssertEqual(transformURLString("vlc://test"), URL(string: "http://test")!, "strip the custom scheme and add http")
        XCTAssertEqual(transformURLString("vlc://ftp//test"), URL(string: "ftp://test")!, "strip the custom scheme and readd :")
        XCTAssertEqual(transformURLString("vlc://ftp://test"), URL(string: "ftp://test")!, "strip custom scheme")
        XCTAssertEqual(transformURLString("vlc://https//test"), URL(string: "https://test")!, "strip the custom scheme and readd :")
        XCTAssertEqual(transformURLString("vlc://https://test"), URL(string: "https://test")!, "strip the custom scheme")
    }
    
}
