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

/// Defines how XLauncher behaves when X-Plane is launched.
enum LaunchBehavior: String, CaseIterable, Identifiable, Codable, Sendable {
    case minimizeToMenuBar = "minimizeToMenuBar"
    case keepWindowOpen = "keepWindowOpen"
    case quitLauncher = "quitLauncher"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .minimizeToMenuBar:
            return "Minimize to Menu Bar (Companion Mode)"
        case .keepWindowOpen:
            return "Keep XLauncher Window Open"
        case .quitLauncher:
            return "Quit XLauncher Immediately"
        }
    }

    var description: String {
        switch self {
        case .minimizeToMenuBar:
            return "Hides the main window and runs as an active flight companion in the macOS Menu Bar."
        case .keepWindowOpen:
            return "Keeps the main launcher window visible alongside X-Plane."
        case .quitLauncher:
            return "Quits XLauncher as soon as X-Plane starts running."
        }
    }
}

/// Defines what happens when X-Plane exits while running in Companion Mode.
enum SimExitBehavior: String, CaseIterable, Identifiable, Codable, Sendable {
    case reopenWindow = "reopenWindow"
    case quitLauncher = "quitLauncher"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .reopenWindow:
            return "Reopen XLauncher Window"
        case .quitLauncher:
            return "Quit XLauncher"
        }
    }

    var description: String {
        switch self {
        case .reopenWindow:
            return "Restores the main launcher window when X-Plane closes."
        case .quitLauncher:
            return "Quits the launcher when X-Plane process terminates."
        }
    }
}
