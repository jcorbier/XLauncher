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

import XCTest
@testable import XPlaneLauncher

@MainActor
final class SimSessionManagerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: .launchBehavior)
        UserDefaults.standard.removeObject(forKey: .simExitBehavior)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: .launchBehavior)
        UserDefaults.standard.removeObject(forKey: .simExitBehavior)
        super.tearDown()
    }

    func testDurationFormatting() {
        XCTAssertEqual(SimSessionManager.formatDuration(0), "00:00:00")
        XCTAssertEqual(SimSessionManager.formatDuration(45), "00:00:45")
        XCTAssertEqual(SimSessionManager.formatDuration(75), "00:01:15")
        XCTAssertEqual(SimSessionManager.formatDuration(3600), "01:00:00")
        XCTAssertEqual(SimSessionManager.formatDuration(3665), "01:01:05")
        XCTAssertEqual(SimSessionManager.formatDuration(36605), "10:10:05")
        XCTAssertEqual(SimSessionManager.formatDuration(-10), "00:00:00")
    }

    func testLaunchBehaviorProperties() {
        for behavior in LaunchBehavior.allCases {
            XCTAssertFalse(behavior.displayName.isEmpty)
            XCTAssertFalse(behavior.description.isEmpty)
            XCTAssertEqual(behavior.id, behavior.rawValue)
        }
    }

    func testSimExitBehaviorProperties() {
        for behavior in SimExitBehavior.allCases {
            XCTAssertFalse(behavior.displayName.isEmpty)
            XCTAssertFalse(behavior.description.isEmpty)
            XCTAssertEqual(behavior.id, behavior.rawValue)
        }
    }

    func testSessionLifecycleTransitions() {
        let manager = SimSessionManager()
        XCTAssertFalse(manager.isSimRunning)
        XCTAssertNil(manager.activeProfileName)
        XCTAssertNil(manager.sessionStartTime)

        var didTerminate = false
        manager.startSession(process: nil, profileName: "IFR Airliner") {
            didTerminate = true
        }

        XCTAssertTrue(manager.isSimRunning)
        XCTAssertEqual(manager.activeProfileName, "IFR Airliner")
        XCTAssertNotNil(manager.sessionStartTime)

        manager.handleProcessTerminated()

        XCTAssertFalse(manager.isSimRunning)
        XCTAssertTrue(didTerminate)
    }

    func testBehaviorUserDefaultsPersistence() {
        let manager = SimSessionManager()
        manager.launchBehavior = .keepWindowOpen
        manager.simExitBehavior = .quitLauncher

        XCTAssertEqual(UserDefaults.standard.string(forKey: .launchBehavior), LaunchBehavior.keepWindowOpen.rawValue)
        XCTAssertEqual(UserDefaults.standard.string(forKey: .simExitBehavior), SimExitBehavior.quitLauncher.rawValue)

        let restoredManager = SimSessionManager()
        XCTAssertEqual(restoredManager.launchBehavior, .keepWindowOpen)
        XCTAssertEqual(restoredManager.simExitBehavior, .quitLauncher)
    }
}
