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
import Observation

@MainActor
@Observable
final class NavdataManager {

    var xPlaneURL: URL? {
        didSet {
            guard xPlaneURL != oldValue else { return }
            scanAndRefresh()
        }
    }

    var launcherDataFolder: URL? {
        didSet {
            guard launcherDataFolder != oldValue else { return }
            scanAndRefresh()
        }
    }

    var addons: [DetectedNavdataItem] = []
    var currentCycleInfo: FMSCycleInfo?
    var catalog: FMSCatalog?
    var backups: [NavdataBackupItem] = []

    var automaticallyCheckNavdataUpdates: Bool {
        didSet {
            UserDefaults.standard.set(automaticallyCheckNavdataUpdates, forKey: .autoCheckNavdataUpdates)
        }
    }

    var isScanning: Bool = false
    var isFetchingPackages: Bool = false
    var logger: ConsoleLogger { ConsoleLogger.shared }

    let authManager: NavigraphAuthManager
    let apiClient: NavigraphAPIClient
    private let scanner = NavdataScanner()

    var isUpdatingAny: Bool {
        addons.contains { $0.isUpdating }
    }

    var hasUpdatesAvailable: Bool {
        addons.contains { $0.isUpdateAvailable }
    }

    private var cacheFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("XPlaneLauncher")
        return appSupport.appendingPathComponent("navdata_index_cache.xml")
    }

    init(authManager: NavigraphAuthManager, xPlaneURL: URL? = nil, launcherDataFolder: URL? = nil) {
        self.authManager = authManager
        self.apiClient = NavigraphAPIClient(authManager: authManager)
        self.xPlaneURL = xPlaneURL
        self.launcherDataFolder = launcherDataFolder

        if UserDefaults.standard.object(forKey: .autoCheckNavdataUpdates) == nil {
            self.automaticallyCheckNavdataUpdates = true
        } else {
            self.automaticallyCheckNavdataUpdates = UserDefaults.standard.bool(forKey: .autoCheckNavdataUpdates)
        }

        // Load cached data.index if available
        loadCachedCatalog()
    }

    // MARK: - Scanning & Refreshing

    func scanAndRefresh() {
        guard let xPlaneURL else {
            self.addons = []
            self.backups = []
            return
        }

        self.isScanning = true
        let launcherFolder = launcherDataFolder
        let currentCatalog = catalog
        let currentScanner = self.scanner

        Task {
            let (scannedAddons, scannedBackups) = await Task.detached(priority: .userInitiated) {
                let addons = currentScanner.scanAddons(xPlaneURL: xPlaneURL, launcherDataFolder: launcherFolder, catalog: currentCatalog)
                let backups = currentScanner.scanBackups(xPlaneURL: xPlaneURL)
                return (addons, backups)
            }.value

            self.addons = scannedAddons
            self.backups = scannedBackups
            self.isScanning = false
        }
    }

    func checkOnlinePackages() async {
        guard case .authenticated = authManager.authState else {
            log("User not logged in to Navigraph, skipping online package check.")
            scanAndRefresh()
            return
        }

        self.isFetchingPackages = true
        log("Checking available navigation data cycles and add-ons from Navigraph...")

        do {
            // 1. Fetch current cycle info
            let cycleInfo = try await apiClient.fetchCurrentCycle()
            self.currentCycleInfo = cycleInfo
            log("Current Navigraph AIRAC cycle: \(cycleInfo.cycle) (Internal ID: \(cycleInfo.cycleInternalId))")

            // 2. Fetch catalog index (data.index XML) and cache it locally
            let fetchedCatalog = try await apiClient.fetchCatalog(cacheDestinationURL: cacheFileURL)
            self.catalog = fetchedCatalog
            log("Fetched data.index with \(fetchedCatalog.addons.count) add-ons (Revision: \(fetchedCatalog.fileRevision)).")

        } catch {
            log("Failed to fetch Navigraph data index: \(error.localizedDescription)", level: .error)
        }

        self.isFetchingPackages = false
        scanAndRefresh()
    }

    // MARK: - Catalog Cache

    private func loadCachedCatalog() {
        guard FileManager.default.fileExists(atPath: cacheFileURL.path),
              let data = try? Data(contentsOf: cacheFileURL),
              let parsed = try? FMSIndexXMLParser.parse(data: data) else {
            return
        }
        self.catalog = parsed
    }

    // MARK: - Update Single Addon

    func updateAddon(_ item: DetectedNavdataItem) async {
        guard let xPlaneURL else { return }

        guard let index = addons.firstIndex(where: { $0.id == item.id }) else { return }
        addons[index].isUpdating = true
        addons[index].statusMessage = "Requesting download URL..."
        addons[index].progress = 0.0

        let cycle = item.latestCycle ?? currentCycleInfo?.cycle ?? catalog?.cycle ?? "2608"
        let internalId = currentCycleInfo?.cycleInternalId ?? catalog?.internalId ?? "\(cycle)r1"

        // Determine masterfile name
        let masterfile: String
        if let direct = item.latestMasterfile, !direct.isEmpty {
            masterfile = direct
        } else if let directDef = item.definition.masterfile, !directDef.isEmpty {
            masterfile = directDef
        } else {
            masterfile = "master_xplane12_\(cycle).zip"
        }

        log("Starting update for '\(item.definition.name)' (Cycle \(cycle), Masterfile: \(masterfile))...")

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("XLauncher_Navdata_\(UUID().uuidString)")
        let zipDownloadURL = tempDir.appendingPathComponent("navdata.zip")
        let extractDir = tempDir.appendingPathComponent("extracted")

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            // 1. Request Download URL from Navigraph
            addons[index].statusMessage = "Authorizing download..."
            let downloadURL = try await apiClient.requestDownloadURL(filename: masterfile, internalId: internalId)

            // 2. Download Package
            addons[index].statusMessage = "Downloading package..."
            try await apiClient.downloadPackageFile(from: downloadURL, destinationURL: zipDownloadURL) { progress, downloaded, total in
                Task { @MainActor in
                    guard let idx = self.addons.firstIndex(where: { $0.id == item.id }) else { return }
                    self.addons[idx].progress = progress * 0.5
                    self.addons[idx].statusMessage = "Downloading: \(ByteCountFormatter.string(fromByteCount: downloaded, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))"
                }
            }

            log("Download complete for '\(item.definition.name)'. Creating safety backup...")
            addons[index].statusMessage = "Creating backup..."
            addons[index].progress = 0.6

            // 3. Safety Backup (offloaded to background)
            try await Task.detached(priority: .userInitiated) {
                try Self.createBackup(for: item, xPlaneURL: xPlaneURL)
            }.value

            // 4. Extract Archive (offloaded to background)
            log("Extracting archive...")
            addons[index].statusMessage = "Extracting..."
            addons[index].progress = 0.75

            try await Task.detached(priority: .userInitiated) {
                try ZipExtractor.extract(archiveAt: zipDownloadURL, to: extractDir)
            }.value

            // 5. Install Extracted Files into Target Directory (offloaded to background)
            log("Installing files to: \(item.targetURL.path)")
            addons[index].statusMessage = "Installing..."
            addons[index].progress = 0.9

            try await Task.detached(priority: .userInitiated) {
                try Self.installExtractedFiles(from: extractDir, to: item.targetURL)
            }.value

            // 6. Cleanup Temp Directory
            try? FileManager.default.removeItem(at: tempDir)

            log("Update completed successfully for '\(item.definition.name)' (Cycle \(cycle)).")
            addons[index].isUpdating = false
            addons[index].isUpdateAvailable = false
            addons[index].currentCycle = cycle
            addons[index].currentRevision = item.latestRevision ?? "1"
            addons[index].statusMessage = "Up to date (Cycle \(cycle))"
            addons[index].progress = 1.0

            // Refresh backups and UI
            let scannedBackups = await Task.detached(priority: .userInitiated) {
                NavdataScanner().scanBackups(xPlaneURL: xPlaneURL)
            }.value
            self.backups = scannedBackups

        } catch {
            try? FileManager.default.removeItem(at: tempDir)
            log("Error updating '\(item.definition.name)': \(error.localizedDescription)", level: .error)
            addons[index].isUpdating = false
            addons[index].statusMessage = "Update failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Update All Addons

    func updateAllAddons() async {
        let toUpdate = addons.filter { $0.isUpdateAvailable }
        log("Starting batch update for \(toUpdate.count) addon(s)...")
        for addon in toUpdate {
            await updateAddon(addon)
        }
        log("Batch update finished.")
    }

    // MARK: - Backup & Restore System

    private nonisolated static func createBackup(for item: DetectedNavdataItem, xPlaneURL: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: item.targetURL.path) else { return }

        let customDataDir = xPlaneURL.appendingPathComponent("Custom Data")
        let backupRootDir = customDataDir.appendingPathComponent("Backup_Data")
        try fileManager.createDirectory(at: backupRootDir, withIntermediateDirectories: true)

        // Remove older backups for the same provider/addon
        cleanupOldBackups(in: backupRootDir, providerName: item.definition.name)

        // Create timestamped backup folder
        let timestamp = Date.now.formatted(date: .numeric, time: .standard)
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ",", with: "")
        let sanitizedName = item.definition.name.replacingOccurrences(of: " ", with: "_")
        let backupSubdir = backupRootDir.appendingPathComponent("\(sanitizedName)_\(timestamp)")
        try fileManager.createDirectory(at: backupSubdir, withIntermediateDirectories: true)

        var backupFiles: [NavdataBackupFileEntry] = []

        // Collect all files in target folder
        if let enumerator = fileManager.enumerator(at: item.targetURL, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                if resourceValues?.isRegularFile == true {
                    let relPath = fileURL.path.replacingOccurrences(of: item.targetURL.path + "/", with: "")
                    let size = Int64(resourceValues?.fileSize ?? 0)
                    backupFiles.append(NavdataBackupFileEntry(relative_path: relPath, size: size, checksum: nil))

                    let destFileURL = backupSubdir.appendingPathComponent(relPath)
                    try fileManager.createDirectory(at: destFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fileManager.copyItem(at: fileURL, to: destFileURL)
                }
            }
        }

        // Write verification.json
        let cycleInfo = NavdataScanner().readCycleInfo(at: item.targetURL)
        let verification = NavdataBackupVerification(
            provider_name: item.definition.name,
            target_relative_path: item.definition.relativeTargetPath,
            cycle: cycleInfo?.cycle,
            airac: cycleInfo?.airac,
            backup_time: ISO8601DateFormatter().string(from: Date()),
            file_count: backupFiles.count,
            files: backupFiles
        )

        let verificationData = try JSONEncoder().encode(verification)
        try verificationData.write(to: backupSubdir.appendingPathComponent("verification.json"))
    }

    private nonisolated static func cleanupOldBackups(in backupRootDir: URL, providerName: String) {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(at: backupRootDir, includingPropertiesForKeys: nil) else { return }

        for dir in entries {
            let verURL = dir.appendingPathComponent("verification.json")
            if let data = try? Data(contentsOf: verURL),
               let ver = try? JSONDecoder().decode(NavdataBackupVerification.self, from: data),
               ver.provider_name == providerName {
                try? fileManager.removeItem(at: dir)
            }
        }
    }

    private nonisolated static func installExtractedFiles(from sourceDir: URL, to targetDir: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: targetDir, withIntermediateDirectories: true)

        // If extracted archive contains a single root folder wrapping everything, dive into it
        var actualSource = sourceDir
        let contents = try fileManager.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        if contents.count == 1, let isDir = try? contents[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDir == true {
            actualSource = contents[0]
        }

        let sourceContents = try fileManager.contentsOfDirectory(at: actualSource, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])

        // 1. Check if an .index package mapping XML file exists
        if let indexFileURL = sourceContents.first(where: { $0.pathExtension.lowercased() == "index" }),
           let indexData = try? Data(contentsOf: indexFileURL),
           let packageIndex = try? FMSPackageIndexParser.parse(data: indexData, simulator: "XP12"),
           !packageIndex.fileMappings.isEmpty {

            for mapping in packageIndex.fileMappings {
                let srcFile = actualSource.appendingPathComponent(mapping.source)
                guard fileManager.fileExists(atPath: srcFile.path) else { continue }

                let destRel = mapping.directory == "." || mapping.directory.isEmpty
                    ? mapping.destination
                    : (mapping.directory as NSString).appendingPathComponent(mapping.destination)
                let destFile = targetDir.appendingPathComponent(destRel)

                try fileManager.createDirectory(at: destFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fileManager.fileExists(atPath: destFile.path) {
                    try fileManager.removeItem(at: destFile)
                }
                try fileManager.moveItem(at: srcFile, to: destFile)
            }

            // Also copy the .index file itself to targetDir
            let destIndexURL = targetDir.appendingPathComponent(indexFileURL.lastPathComponent)
            if fileManager.fileExists(atPath: destIndexURL.path) {
                try fileManager.removeItem(at: destIndexURL)
            }
            try fileManager.copyItem(at: indexFileURL, to: destIndexURL)
            return
        }

        // 2. Standard direct file installation (for zip archives without .index)
        for item in sourceContents {
            let destURL = targetDir.appendingPathComponent(item.lastPathComponent)
            if fileManager.fileExists(atPath: destURL.path) {
                try fileManager.removeItem(at: destURL)
            }
            try fileManager.moveItem(at: item, to: destURL)
        }
    }

    func restoreBackup(_ backup: NavdataBackupItem) throws {
        guard let xPlaneURL else { return }
        let fileManager = FileManager.default
        let targetRelPath = backup.verification.target_relative_path ?? "Custom Data"
        let targetDir = xPlaneURL.appendingPathComponent(targetRelPath)

        log("Restoring backup from '\(backup.folderName)' to '\(targetRelPath)'...")

        for fileEntry in backup.verification.files {
            let srcFile = backup.folderURL.appendingPathComponent(fileEntry.relative_path)
            let dstFile = targetDir.appendingPathComponent(fileEntry.relative_path)

            if fileManager.fileExists(atPath: srcFile.path) {
                try fileManager.createDirectory(at: dstFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fileManager.fileExists(atPath: dstFile.path) {
                    try fileManager.removeItem(at: dstFile)
                }
                try fileManager.copyItem(at: srcFile, to: dstFile)
            }
        }

        // Remove restored backup folder
        try fileManager.removeItem(at: backup.folderURL)
        log("Backup restore complete.")

        scanAndRefresh()
    }

    func deleteBackup(_ backup: NavdataBackupItem) {
        try? FileManager.default.removeItem(at: backup.folderURL)
        log("Deleted backup '\(backup.folderName)'.")
        if let xPlaneURL {
            self.backups = scanner.scanBackups(xPlaneURL: xPlaneURL)
        }
    }

    // MARK: - Supported Addons & Custom Mapping

    var supportedXP12Addons: [FMSAddonDefinition] {
        guard let catalog else { return [] }
        return catalog.addons.filter { addon in
            !addon.name.contains("X-Plane 12") &&
            addon.mappings.contains { $0.simulator == "XP12" }
        }.sorted { $0.name < $1.name }
    }

    func computeSuggestedPath(for addon: FMSAddonDefinition) -> String {
        scanner.computeSuggestedPath(for: addon, xPlaneURL: xPlaneURL, launcherDataFolder: launcherDataFolder)
    }

    func addMapping(
        addon: FMSAddonDefinition?,
        name: String,
        formatKey: String,
        relativeTargetPath: String
    ) {
        let id = addon?.guid ?? UUID().uuidString
        let addonName = addon?.name ?? name
        let key = addon != nil ? (addon!.name.lowercased().replacingOccurrences(of: " ", with: "-")) : formatKey
        let masterfile = addon?.masterfile
        let isCustom = (addon == nil)

        let def = NavdataAddonDefinition(
            id: id,
            name: addonName,
            formatKey: key,
            relativeTargetPath: relativeTargetPath,
            masterfile: masterfile,
            isCustom: isCustom
        )
        NavdataCatalog.saveCustomAddon(def)
        log("Added navdata mapping: '\(addonName)' -> \(relativeTargetPath)")
        scanAndRefresh()
    }

    func deleteCustomMapping(id: String) {
        NavdataCatalog.deleteCustomAddon(id: id)
        log("Removed custom navdata mapping with id: \(id)")
        scanAndRefresh()
    }

    func log(_ message: String, level: LogLevel = .info) {
        ConsoleLogger.shared.log(message, category: .navdata, level: level)
    }

    func clearLogs() {
        ConsoleLogger.shared.clear(category: .navdata)
    }
}
