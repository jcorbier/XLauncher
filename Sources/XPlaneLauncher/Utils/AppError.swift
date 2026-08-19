//
//  Copyright (c) 2026 Jeremie Corbier
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import Foundation

enum AppError: LocalizedError, Sendable {
    case pathNotFound(String)
    case xPlaneNotFound(URL)
    case scriptExecutionFailed(path: String, underlyingError: String)
    case scriptNotFound(String)
    case symlinkFailed(source: String, target: String, reason: String)
    case invalidConfig(String)
    case networkError(String)
    case decodingError(String)
    case custom(String)

    var errorDescription: String? {
        switch self {
        case .pathNotFound(let path):
            return "Path not found: \(path)"
        case .xPlaneNotFound(let url):
            return "X-Plane application not found at '\(url.path)'"
        case .scriptExecutionFailed(let path, let underlying):
            return "Failed to run script at '\(path)': \(underlying)"
        case .scriptNotFound(let path):
            return "Script file does not exist at '\(path)'"
        case .symlinkFailed(let source, let target, let reason):
            return "Failed to link '\(source)' -> '\(target)': \(reason)"
        case .invalidConfig(let msg):
            return "Invalid configuration: \(msg)"
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .decodingError(let msg):
            return "Failed to parse data: \(msg)"
        case .custom(let msg):
            return msg
        }
    }
}
