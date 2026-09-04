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

@MainActor
final class LaunchService {
    static let shared = LaunchService()

    private var fileManager: FileManager { FileManager.default }

    func executeShellScript(
        at path: String,
        profileName: String,
        globalEnv: [ScriptEnvVar],
        profileEnv: [ScriptEnvVar]
    ) throws {
        guard fileManager.fileExists(atPath: path) else {
            throw AppError.scriptNotFound(path)
        }

        let process = Process()
        let isExecutable = fileManager.isExecutableFile(atPath: path)
        let isShellScript = path.hasSuffix(".sh") || path.hasSuffix(".zsh") || path.hasSuffix(".bash") || !isExecutable

        if isShellScript {
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [path]
        } else {
            process.executableURL = URL(fileURLWithPath: path)
        }

        process.currentDirectoryURL = URL(fileURLWithPath: path).deletingLastPathComponent()

        var env = ProcessInfo.processInfo.environment

        // 1. Global environment variables
        for envVar in globalEnv where !envVar.key.isEmpty {
            env[envVar.key] = envVar.value
        }

        // 2. Per-profile environment variables
        for envVar in profileEnv where !envVar.key.isEmpty {
            env[envVar.key] = envVar.value
        }

        // 3. System profile name variable
        env["XLAUNCHER_PROFILE"] = profileName

        process.environment = env
        ConsoleLogger.shared.log("Executing shell script at '\(path)' (profile: \(profileName))", category: .launch)
        try process.run()
    }

    func launchXPlane(
        at xPlanePath: URL,
        arguments: [String] = [],
        onSuccess: @escaping @MainActor () -> Void,
        onFailure: @escaping @MainActor (Error) -> Void
    ) {
        let appURL = xPlanePath.appendingPathComponent("X-Plane.app")
        guard fileManager.fileExists(atPath: appURL.path) else {
            ConsoleLogger.shared.log("X-Plane.app not found in \(xPlanePath.path)", category: .launch, level: .error)
            onFailure(AppError.xPlaneNotFound(appURL))
            return
        }

        if arguments.isEmpty {
            ConsoleLogger.shared.log("Launching X-Plane from \(appURL.path)", category: .launch)
        } else {
            ConsoleLogger.shared.log("Launching X-Plane from \(appURL.path) with arguments: \(arguments.joined(separator: " "))", category: .launch)
        }

        let workspace = NSWorkspace.shared
        let config = NSWorkspace.OpenConfiguration()
        if !arguments.isEmpty {
            config.arguments = arguments
        }
        workspace.openApplication(at: appURL, configuration: config) { _, error in
            Task { @MainActor in
                if let error = error {
                    ConsoleLogger.shared.log("Failed to launch X-Plane: \(error.localizedDescription)", category: .launch, level: .error)
                    onFailure(error)
                } else {
                    ConsoleLogger.shared.log("Launched X-Plane successfully", category: .launch)
                    onSuccess()
                }
            }
        }
    }
}
