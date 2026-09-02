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

import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class SimSessionManager {
    static let shared = SimSessionManager()

    // MARK: - Configuration Properties
    var launchBehavior: LaunchBehavior {
        didSet {
            UserDefaults.standard.set(launchBehavior.rawValue, forKey: .launchBehavior)
        }
    }

    var simExitBehavior: SimExitBehavior {
        didSet {
            UserDefaults.standard.set(simExitBehavior.rawValue, forKey: .simExitBehavior)
        }
    }

    // MARK: - Live Session State
    private(set) var isSimRunning: Bool = false
    private(set) var activeProcess: NSRunningApplication?
    private(set) var activeProfileName: String?
    private(set) var sessionStartTime: Date?
    private(set) var flightDuration: TimeInterval = 0

    // MARK: - Internal Timers & Observers
    private var durationTimer: Timer?
    private var terminationObserver: NSObjectProtocol?
    private var onSessionTerminated: (() -> Void)?

    init() {
        if let raw = UserDefaults.standard.string(forKey: .launchBehavior),
           let behavior = LaunchBehavior(rawValue: raw) {
            self.launchBehavior = behavior
        } else {
            self.launchBehavior = .minimizeToMenuBar
        }

        if let raw = UserDefaults.standard.string(forKey: .simExitBehavior),
           let behavior = SimExitBehavior(rawValue: raw) {
            self.simExitBehavior = behavior
        } else {
            self.simExitBehavior = .reopenWindow
        }
    }

    // MARK: - Session Lifecycle

    /// Starts tracking a running X-Plane simulator instance.
    func startSession(
        process: NSRunningApplication?,
        profileName: String?,
        onTerminate: (() -> Void)? = nil
    ) {
        self.activeProcess = process
        self.activeProfileName = profileName
        self.sessionStartTime = Date()
        self.flightDuration = 0
        self.isSimRunning = true
        self.onSessionTerminated = onTerminate

        ConsoleLogger.shared.log("Started simulator tracking session (Profile: \(profileName ?? "None"), PID: \(process?.processIdentifier ?? -1))", category: .launch)

        // Start live duration timer and termination fallback poll
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self, self.isSimRunning else { return }

                if let process = self.activeProcess, process.isTerminated {
                    self.handleProcessTerminated()
                    return
                }

                if let start = self.sessionStartTime {
                    self.flightDuration = Date().timeIntervalSince(start)
                }
            }
        }

        // Observe application termination
        if let observer = terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            terminationObserver = nil
        }

        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let terminatedApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let terminatedPID = terminatedApp?.processIdentifier
            let terminatedBundleID = terminatedApp?.bundleIdentifier
            let terminatedName = terminatedApp?.localizedName
            let hasXPExecutable = terminatedApp?.executableURL?.lastPathComponent.hasPrefix("X-Plane") == true

            MainActor.assumeIsolated {
                guard let self = self, self.isSimRunning else { return }
                if let targetPID = self.activeProcess?.processIdentifier, let termPID = terminatedPID, termPID == targetPID {
                    self.handleProcessTerminated()
                } else if terminatedBundleID == "com.laminar-research.X-Plane" ||
                            terminatedName == "X-Plane" ||
                            hasXPExecutable {
                    self.handleProcessTerminated()
                }
            }
        }
    }

    /// Handles simulation process termination.
    func handleProcessTerminated() {
        guard isSimRunning else { return }
        ConsoleLogger.shared.log("Simulator process termination detected", category: .launch)

        endSession()
        onSessionTerminated?()
    }

    /// Ends the current tracking session and cleans up observers.
    func endSession() {
        durationTimer?.invalidate()
        durationTimer = nil

        if let observer = terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            terminationObserver = nil
        }

        isSimRunning = false
        activeProcess = nil
    }

    /// Force terminates the running X-Plane process if unresponsive.
    func forceQuitSimulator() {
        // 1. Resolve active or running X-Plane instance
        var targetProcess = activeProcess

        if targetProcess == nil || targetProcess?.isTerminated == true {
            targetProcess = NSWorkspace.shared.runningApplications.first(where: {
                $0.bundleIdentifier == "com.laminar-research.X-Plane" ||
                $0.localizedName == "X-Plane" ||
                $0.executableURL?.lastPathComponent.hasPrefix("X-Plane") == true
            })
        }

        if let process = targetProcess {
            let pid = process.processIdentifier
            ConsoleLogger.shared.log("Force quitting X-Plane (PID \(pid))", category: .launch, level: .warn)
            process.forceTerminate()
            kill(pid, SIGKILL)
        } else {
            ConsoleLogger.shared.log("No specific X-Plane process identified, issuing pkill", category: .launch, level: .warn)
        }

        // As a safeguard, also invoke pkill for X-Plane to ensure no detached simulator process remains
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-9", "-x", "X-Plane"]
        try? pkill.run()

        handleProcessTerminated()
    }

    // MARK: - Helpers

    /// Formats a time interval into a human-readable duration string `HH:MM:SS`.
    static func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(max(0, duration))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    var formattedFlightDuration: String {
        Self.formatDuration(flightDuration)
    }
}
