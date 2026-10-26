/*****************************************************************************
 * DiscourseAPIError.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * Every failure of the discourse API surfaces as one of these cases. Screens
 * never format transport details themselves: they show `userMessage`, which is
 * the generic copy required by the product spec.
 *****************************************************************************/

import Foundation

enum DiscourseAPIError: Error {
    /// The build did not inject an API key or a usable base URL.
    case missingConfiguration
    /// A request URL could not be built from the base URL and parameters.
    case invalidURL(path: String)
    /// No usable network connection.
    case offline(URLError?)
    /// The request exceeded the read timeout.
    case timedOut
    /// The server answered with a non-2xx status.
    case http(status: Int)
    /// The response body was not the expected JSON shape.
    case decoding(Error)
    /// Any other transport failure.
    case transport(Error)
    /// The caller cancelled the request.
    case cancelled

    /// True when retrying later, or falling back to cached content, makes sense.
    var isConnectivityFailure: Bool {
        switch self {
        case .offline, .timedOut, .transport:
            return true
        case .http(let status):
            return status >= 500
        case .missingConfiguration, .invalidURL, .decoding, .cancelled:
            return false
        }
    }

    /// The single copy the product shows for a failed request.
    var userMessage: String {
        DiscourseErrorCopy.serverFailure
    }

    /// Short, secret-free description for diagnostics.
    var diagnosticDescription: String {
        switch self {
        case .missingConfiguration:
            return "missing API configuration"
        case .invalidURL(let path):
            return "invalid URL for /\(path)"
        case .offline(let error):
            return "offline (\(error?.code.rawValue ?? URLError.notConnectedToInternet.rawValue))"
        case .timedOut:
            return "timed out"
        case .http(let status):
            return "HTTP \(status)"
        case .decoding(let error):
            return "decoding failed (\(type(of: error)))"
        case .transport(let error):
            if let urlError = error as? URLError {
                return "transport (\(urlError.code.rawValue))"
            }
            return "transport (\(type(of: error)))"
        case .cancelled:
            return "cancelled"
        }
    }
}
