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

final class XPlaneLogAnalyzerTests: XCTestCase {
    var tempDirectory: URL!
    var parser: XPlaneLogParser!
    var engine: XPlaneLogDiagnosticsEngine!

    override func setUp() {
        super.setUp()
        parser = XPlaneLogParser()
        engine = XPlaneLogDiagnosticsEngine()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    func testLogParserTimestampsAndTags() {
        let sampleLog = """
        0:00:00.000 I/SYS: MAC IBM clean exit
        0:00:05.120 I/PLG: Loaded: /Users/test/X-Plane 12/Resources/plugins/FlyWithLua/mac_x64/FlyWithLua.xpl (FlyWithLua NG+).
        0:00:08.500 W/SCN: Custom Scenery/Global Airports/Earth nav data/apt.dat: Warning on runway 09L
        0:00:15.000 E/GFX: Metal device error: Out of memory
        Continuation stack line without timestamp
        """

        let entries = parser.parseString(sampleLog)
        XCTAssertEqual(entries.count, 5)

        // Entry 1
        XCTAssertEqual(entries[0].lineNumber, 1)
        XCTAssertEqual(entries[0].timestampSeconds, 0.0)
        XCTAssertEqual(entries[0].subsystem, .system)
        XCTAssertEqual(entries[0].level, .info)

        // Entry 2
        XCTAssertEqual(entries[1].lineNumber, 2)
        XCTAssertEqual(entries[1].timestampSeconds, 5.120)
        XCTAssertEqual(entries[1].subsystem, .lua) // FlyWithLua heuristic
        XCTAssertEqual(entries[1].level, .info)

        // Entry 3
        XCTAssertEqual(entries[2].lineNumber, 3)
        XCTAssertEqual(entries[2].timestampSeconds, 8.500)
        XCTAssertEqual(entries[2].subsystem, .scenery)
        XCTAssertEqual(entries[2].level, .warn)

        // Entry 4
        XCTAssertEqual(entries[3].lineNumber, 4)
        XCTAssertEqual(entries[3].timestampSeconds, 15.000)
        XCTAssertEqual(entries[3].subsystem, .graphics)
        XCTAssertEqual(entries[3].level, .error)

        // Entry 5 (inherits previous timestamp)
        XCTAssertEqual(entries[4].lineNumber, 5)
        XCTAssertEqual(entries[4].timestampSeconds, 15.000)
    }

    func testDetectPluginCrash() {
        let crashLog = """
        0:00:00.000 I/SYS: Starting X-Plane
        0:00:05.000 I/PLG: Loaded: /Plugins/BetterPushback/mac_x64/BetterPushback.xpl (BetterPushback).
        0:01:20.100 E/SYS: +-------------------------------------------------------------------
        0:01:20.100 E/SYS: | This application has crashed because of the plugin: BetterPushback
        0:01:20.100 E/SYS: +-------------------------------------------------------------------
        0:01:20.100 E/SYS: Backtrace:
        0:01:20.100 E/SYS: 0  BetterPushback.xpl  0x0000000123456789 bp_calculate_push + 42
        0:01:20.100 E/SYS: 1  X-Plane             0x0000000100010000 XPLMPluginCallback + 120
        """

        let entries = parser.parseString(crashLog)
        let fileItem = LogFileItem(url: tempDirectory.appendingPathComponent("Log.txt"), displayName: "Log.txt", sourceType: .current)
        let report = engine.analyze(entries: entries, fileItem: fileItem)

        guard case .crashed(let crash) = report.status else {
            XCTFail("Expected status to be crashed")
            return
        }

        XCTAssertEqual(crash.category, .pluginCrash)
        XCTAssertEqual(crash.offendingPluginOrSubsystem, "BetterPushback")
        XCTAssertTrue(crash.backtrace.contains(where: { $0.contains("bp_calculate_push") }))
    }

    func testDetectFatalSignalAndMemoryExhaustion() {
        let oomLog = """
        0:00:00.000 I/SYS: Starting sim
        0:05:30.000 E/GFX: MTLCommandBuffer failed: Out of memory (0x1)
        0:05:30.100 E/SYS: VRAM allocation failed. Terminating graphics device.
        """

        let entries = parser.parseString(oomLog)
        let fileItem = LogFileItem(url: tempDirectory.appendingPathComponent("Log.txt"), displayName: "Log.txt", sourceType: .current)
        let report = engine.analyze(entries: entries, fileItem: fileItem)

        guard case .crashed(let crash) = report.status else {
            XCTFail("Expected crash status")
            return
        }

        XCTAssertEqual(crash.category, .memoryExhaustion)
    }

    func testDynamicMissingSceneryExtraction() {
        let sceneryLog = """
        0:00:10.000 E/SCN: Custom Scenery/KLAX - Los Angeles/Earth nav data/+30-120/+33-119.dsf:
        0:00:10.001 E/SCN: Unable to load object file: opensceneryx/objects/buildings/hangars/large.obj
        0:00:10.002 E/SCN: Failed to find resource 'MisterX_Library/Airport/Jetways/jetway_glass.obj', referenced by scenery package 'Custom Scenery/KLAX - Los Angeles/'.
        0:00:10.003 E/SCN: Custom Scenery/EDDF - Frankfurt/: Unable to load object file: Custom Scenery/EDDF - Frankfurt/objects/terminal1.obj
        0:00:10.004 E/SCN: Failed to find resource 'SAM_Library/hangars/open_hangar.obj'
        """

        let entries = parser.parseString(sceneryLog)
        let fileItem = LogFileItem(url: tempDirectory.appendingPathComponent("Log.txt"), displayName: "Log.txt", sourceType: .current)
        let report = engine.analyze(entries: entries, fileItem: fileItem)

        XCTAssertEqual(report.missingSceneryIssues.count, 4)

        // Verify dynamic extraction grouped by package/library namespace without hardcoded databases
        XCTAssertTrue(report.missingSceneryByPackage.keys.contains("opensceneryx"))
        XCTAssertTrue(report.missingSceneryByPackage.keys.contains("MisterX_Library"))
        XCTAssertTrue(report.missingSceneryByPackage.keys.contains("EDDF - Frankfurt"))
        XCTAssertTrue(report.missingSceneryByPackage.keys.contains("SAM_Library"))

        let osxIssues = report.missingSceneryByPackage["opensceneryx"]
        XCTAssertEqual(osxIssues?.count, 1)
        XCTAssertEqual(osxIssues?.first?.assetType, .object)
    }

    func testFlyWithLuaAndSASLErrorTracing() {
        let scriptLog = """
        0:00:05.000 I/PLG: Loaded: FlyWithLua.xpl
        0:00:12.000 E/LUA: FlyWithLua Error: The script 'Aircraft_Lights_Control.lua' failed with error: attempt to index a nil value
        0:00:12.001 E/LUA: stack traceback:
        0:00:12.002 E/LUA:   Aircraft_Lights_Control.lua:45: in function 'update_lights'
        0:00:12.003 E/LUA:   Aircraft_Lights_Control.lua:90: in main chunk
        0:00:20.000 E/SASL: [SASL ERROR] avionics_logic.lua: Failed to initialize autopilot state
        0:00:20.001 E/SASL: stack traceback:
        0:00:20.002 E/SASL:   avionics_logic.lua:12: in function 'init_ap'
        """

        let entries = parser.parseString(scriptLog)
        let fileItem = LogFileItem(url: tempDirectory.appendingPathComponent("Log.txt"), displayName: "Log.txt", sourceType: .current)
        let report = engine.analyze(entries: entries, fileItem: fileItem)

        XCTAssertEqual(report.scriptErrors.count, 2)

        let luaErr = report.scriptErrors.first(where: { $0.engine == .flyWithLua })
        XCTAssertNotNil(luaErr)
        XCTAssertEqual(luaErr?.scriptOrModuleName, "Aircraft_Lights_Control.lua")
        XCTAssertEqual(luaErr?.stackTrace.count, 2)

        let saslErr = report.scriptErrors.first(where: { $0.engine == .sasl })
        XCTAssertNotNil(saslErr)
        XCTAssertEqual(saslErr?.scriptOrModuleName, "avionics_logic.lua")
    }

    func testStartupPerformanceProfiling() {
        let timingLog = """
        0:00:00.000 I/SYS: Sim booting
        0:00:02.000 I/PLG: Loaded: /Plugins/TerrainRadar/mac_x64/TerrainRadar.xpl (TerrainRadar).
        0:00:07.500 I/PLG: Loaded: /Plugins/TolissA321/mac_x64/TolissA321.xpl (Toliss A321 Systems).
        0:00:12.000 I/SCN: DSFLoad: Loaded +37-122.dsf
        0:00:15.000 I/SYS: Fly with X-Plane
        """

        let entries = parser.parseString(timingLog)
        let fileItem = LogFileItem(url: tempDirectory.appendingPathComponent("Log.txt"), displayName: "Log.txt", sourceType: .current)
        let report = engine.analyze(entries: entries, fileItem: fileItem)

        XCTAssertEqual(report.startupTimings.count, 3)
        XCTAssertEqual(report.totalStartupSeconds, 15.0)

        let toliss = report.startupTimings.first(where: { $0.name.contains("Toliss") })
        XCTAssertNotNil(toliss)
        XCTAssertEqual(toliss?.durationSeconds, 5.5) // from 2.0 to 7.5
    }

    func testCleanExitVsAbnormal() {
        let cleanLog = """
        0:00:00.000 I/SYS: Boot
        0:01:00.000 I/SYS: MAC clean exit
        """
        let cleanEntries = parser.parseString(cleanLog)
        let fileItem = LogFileItem(url: tempDirectory.appendingPathComponent("Log.txt"), displayName: "Log.txt", sourceType: .current)
        let cleanReport = engine.analyze(entries: cleanEntries, fileItem: fileItem)
        XCTAssertEqual(cleanReport.status, .cleanExit)

        let incompleteLog = """
        0:00:00.000 I/SYS: Boot
        0:00:45.000 I/FLT: Flight in progress
        """
        let incompleteEntries = parser.parseString(incompleteLog)
        let incReport = engine.analyze(entries: incompleteEntries, fileItem: fileItem)
        XCTAssertEqual(incReport.status, .runningOrIncomplete)
    }

    @MainActor
    func testArchiveDiscoveryAndSorting() throws {
        let xPlaneDir = tempDirectory.appendingPathComponent("X-Plane 12")
        let archiveDir = xPlaneDir.appendingPathComponent("Output").appendingPathComponent("Log Archive")
        try FileManager.default.createDirectory(at: archiveDir, withIntermediateDirectories: true)

        let logTxt = xPlaneDir.appendingPathComponent("Log.txt")
        try "0:00:00.000 I/SYS: Boot".write(to: logTxt, atomically: true, encoding: .utf8)

        let archive1 = archiveDir.appendingPathComponent("Log_20260830_120000.txt")
        try "0:00:00.000 I/SYS: Old archive".write(to: archive1, atomically: true, encoding: .utf8)

        let archive2 = archiveDir.appendingPathComponent("Log_20260901_100000.txt")
        try "0:00:00.000 I/SYS: Newer archive".write(to: archive2, atomically: true, encoding: .utf8)

        let service = XPlaneLogArchiveService()
        service.discoverLogFiles(for: xPlaneDir)

        XCTAssertEqual(service.availableLogFiles.count, 3)
        XCTAssertEqual(service.availableLogFiles.first?.sourceType, .current)
    }

    func testMarkdownReportGeneration() {
        let sampleLog = """
        0:00:00.000 I/SYS: Sim starting
        0:00:02.000 I/PLG: Loaded: /Plugins/TestPlugin.xpl (TestPlugin).
        0:00:05.000 E/SCN: Unable to load object file: custom_lib/terminal.obj
        0:00:08.000 E/LUA: FlyWithLua Error: The script 'test.lua' failed with error: crash
        0:00:10.000 E/SYS: This application has crashed because of the plugin: TestPlugin
        """
        let entries = parser.parseString(sampleLog)
        let fileItem = LogFileItem(url: tempDirectory.appendingPathComponent("Log.txt"), displayName: "Log.txt", sourceType: .current)
        let report = engine.analyze(entries: entries, fileItem: fileItem)

        let md = report.generateMarkdownReport()
        XCTAssertTrue(md.contains("# X-Plane Log Diagnostics Report"))
        XCTAssertTrue(md.contains("Crash Diagnostics"))
        XCTAssertTrue(md.contains("TestPlugin"))
        XCTAssertTrue(md.contains("Missing Scenery Assets"))
        XCTAssertTrue(md.contains("FlyWithLua"))
    }
}
