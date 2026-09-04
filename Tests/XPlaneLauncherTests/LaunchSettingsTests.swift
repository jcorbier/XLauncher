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
final class LaunchSettingsTests: XCTestCase {
    private var pluginManager: PluginManager!
    private let defaults = UserDefaults.standard

    override func setUp() async throws {
        try await super.setUp()
        defaults.removeObject(forKey: .xPlaneLaunchArguments)
        pluginManager = PluginManager()
    }

    override func tearDown() async throws {
        defaults.removeObject(forKey: .xPlaneLaunchArguments)
        pluginManager = nil
        try await super.tearDown()
    }

    func testParsedLaunchArgumentsEmpty() {
        pluginManager.launchArguments = ""
        XCTAssertTrue(pluginManager.parsedLaunchArguments.isEmpty)

        pluginManager.launchArguments = "   "
        XCTAssertTrue(pluginManager.parsedLaunchArguments.isEmpty)
    }

    func testParsedLaunchArgumentsSingle() {
        pluginManager.launchArguments = "--force_windowed"
        XCTAssertEqual(pluginManager.parsedLaunchArguments, ["--force_windowed"])
    }

    func testParsedLaunchArgumentsMultiple() {
        pluginManager.launchArguments = "--force_windowed --no_sound --fps_test=1"
        XCTAssertEqual(pluginManager.parsedLaunchArguments, ["--force_windowed", "--no_sound", "--fps_test=1"])
    }

    func testParsedLaunchArgumentsWithExtraWhitespace() {
        pluginManager.launchArguments = "   --force_windowed    --pref:draw_clouds=0   --no_sound  "
        XCTAssertEqual(pluginManager.parsedLaunchArguments, ["--force_windowed", "--pref:draw_clouds=0", "--no_sound"])
    }

    func testLaunchArgumentsPersistence() {
        pluginManager.launchArguments = "--force_windowed --no_sound"
        XCTAssertEqual(defaults.string(forKey: .xPlaneLaunchArguments), "--force_windowed --no_sound")

        // Recreating or creating a new instance reads the saved value
        let newManager = PluginManager()
        XCTAssertEqual(newManager.launchArguments, "--force_windowed --no_sound")
        XCTAssertEqual(newManager.parsedLaunchArguments, ["--force_windowed", "--no_sound"])
    }
}
