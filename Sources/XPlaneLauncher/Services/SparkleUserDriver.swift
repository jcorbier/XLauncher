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
import Sparkle
import AppKit

@MainActor
final class SparkleCustomUserDriver: NSObject, SPUUserDriver {
    weak var updateManager: AppUpdateManager?

    private var totalBytesExpected: UInt64 = 0
    private var totalBytesDownloaded: UInt64 = 0
    private var updateChoiceReply: ((SPUUserUpdateChoice) -> Void)?
    private var downloadCancellation: (() -> Void)?

    init(updateManager: AppUpdateManager? = nil) {
        self.updateManager = updateManager
        super.init()
    }

    func cancelDownload() {
        downloadCancellation?()
        downloadCancellation = nil
        if let reply = updateChoiceReply {
            updateChoiceReply = nil
            reply(.dismiss)
        }
    }

    func proceedWithInstall() {
        if let reply = updateChoiceReply {
            updateChoiceReply = nil
            reply(.install)
        }
    }

    // MARK: - SPUUserDriver

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        // Handled by our AppUpdateManager UI
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        ConsoleLogger.shared.log("Sparkle: Update found version \(appcastItem.displayVersionString) (\(appcastItem.versionString))", category: .updates, level: .info)
        // If user already initiated update from UI, proceed with install immediately
        if updateManager?.isSparkleUpdating == true {
            reply(.install)
        } else {
            self.updateChoiceReply = reply
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        // We show our own release notes from GitHub API
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {
        ConsoleLogger.shared.log("Sparkle: Failed to download release notes: \(error.localizedDescription)", category: .updates, level: .debug)
    }

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        ConsoleLogger.shared.log("Sparkle: Update check returned no newer version (\(error.localizedDescription))", category: .updates, level: .info)
        updateManager?.sparkleStatus = ""
        updateManager?.isSparkleUpdating = false
        updateManager?.statusMessage = "No update available via updater feed"
        acknowledgement()
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        let errorDesc = error.localizedDescription
        ConsoleLogger.shared.log("Sparkle: Updater error: \(errorDesc)", category: .updates, level: .error)
        updateManager?.sparkleErrorMessage = errorDesc
        updateManager?.isSparkleUpdating = false
        updateManager?.sparkleStatus = "Update failed: \(errorDesc)"
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        ConsoleLogger.shared.log("Sparkle: Download initiated", category: .updates, level: .info)
        self.downloadCancellation = cancellation
        self.totalBytesDownloaded = 0
        self.totalBytesExpected = 0
        updateManager?.isSparkleUpdating = true
        updateManager?.sparkleDownloadProgress = 0.0
        updateManager?.sparkleStatus = "Downloading update..."
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        self.totalBytesExpected = expectedContentLength
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        self.totalBytesDownloaded += length
        if totalBytesExpected > 0 {
            let progress = Double(totalBytesDownloaded) / Double(totalBytesExpected)
            updateManager?.sparkleDownloadProgress = min(max(progress, 0.0), 1.0)
            
            let formattedDownloaded = ByteCountFormatter.string(fromByteCount: Int64(totalBytesDownloaded), countStyle: .file)
            let formattedTotal = ByteCountFormatter.string(fromByteCount: Int64(totalBytesExpected), countStyle: .file)
            updateManager?.sparkleStatus = "Downloading update (\(formattedDownloaded) / \(formattedTotal))..."
        } else {
            let formattedDownloaded = ByteCountFormatter.string(fromByteCount: Int64(totalBytesDownloaded), countStyle: .file)
            updateManager?.sparkleStatus = "Downloading update (\(formattedDownloaded))..."
        }
    }

    func showDownloadDidStartExtractingUpdate() {
        ConsoleLogger.shared.log("Sparkle: Extracting update archive...", category: .updates, level: .info)
        updateManager?.sparkleStatus = "Extracting update..."
        updateManager?.sparkleDownloadProgress = 1.0
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        updateManager?.sparkleStatus = "Extracting update (\(Int(progress * 100))%)..."
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        ConsoleLogger.shared.log("Sparkle: Ready to install and relaunch", category: .updates, level: .info)
        updateManager?.sparkleStatus = "Ready to relaunch..."
        reply(.install)
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        ConsoleLogger.shared.log("Sparkle: Installing update and restarting app...", category: .updates, level: .info)
        updateManager?.sparkleStatus = "Installing update & restarting..."
        if !applicationTerminated {
            // Exit directly to allow Sparkle's Autoupdate helper to swap the bundle and relaunch,
            // avoiding AppKit modal close validation that triggers NSBeep().
            exit(0)
        }
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func dismissUpdateInstallation() {
        updateManager?.isSparkleUpdating = false
        updateManager?.sparkleDownloadProgress = 0.0
        updateManager?.sparkleStatus = ""
        downloadCancellation = nil
        updateChoiceReply = nil
    }
}
