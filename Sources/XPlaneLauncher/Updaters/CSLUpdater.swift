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
import SwiftUI
import CryptoKit

// MARK: - CSL Data Models

enum CSLPackageStatus: String, Codable, Sendable {
    case notInstalled = "not_installed"
    case upToDate = "up_to_date"
    case needsUpdate = "needs_update"
    case checking = "checking"
    case updating = "updating"
    case error = "error"
}

struct CSLFileItem: Codable, Equatable, Hashable, Sendable {
    let path: String
    let sizeBytes: Int64
    let md5: String?
    let date: String
    let time: String
}

struct CSLPackage: Identifiable, Equatable, Hashable, Sendable {
    let id = UUID()
    let name: String
    var title: String
    var totalSizeBytes: Int64
    var fileCount: Int
    var status: CSLPackageStatus = .notInstalled
    var filesToUpdate: Int = 0
    var updateSizeBytes: Int64 = 0
    var lastUpdated: String = ""
    var statusMessage: String = "Not installed"
    var isInstalled: Bool = false
    var downloadProgress: Double = 0.0
    var downloadedBytes: Int64 = 0
    var currentDownloadFile: String = ""
    var files: [CSLFileItem] = []
    
    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSizeBytes, countStyle: .file)
    }
    
    var formattedUpdateSize: String {
        ByteCountFormatter.string(fromByteCount: updateSizeBytes, countStyle: .file)
    }
}

// MARK: - CSL Index Parser

struct CSLIndexEntry {
    let entryType: Int // 11 = package header, 10 = file, 15 = dir
    let path: String
    let sizeBytes: Int64
    let md5: String?
    let date: String
    let time: String
}

struct CSLRawPackage: Sendable {
    let name: String
    var headerSize: Int64
    var headerDate: String
    var headerTime: String
    var files: [CSLFileItem]
}

final class CSLIndexParser: Sendable {
    static func parseIndex(content: String) -> [CSLRawPackage] {
        var packageMap: [String: CSLRawPackage] = [:]
        
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("0 ") {
                continue
            }
            
            let parts = trimmed.components(separatedBy: "%")
            guard parts.count >= 6 else { continue }
            guard let entryType = Int(parts[0]), entryType == 10 || entryType == 11 else { continue }
            
            let path = parts[1]
            let sizeBytes = Int64(parts[2]) ?? 0
            let rawMd5 = parts[3]
            let md5: String? = (entryType == 10 && !rawMd5.isEmpty && rawMd5 != "Reserve") ? rawMd5.lowercased() : nil
            let date = parts[4]
            let time = parts[5]
            
            if entryType == 11 {
                var pkg = packageMap[path] ?? CSLRawPackage(name: path, headerSize: 0, headerDate: "", headerTime: "", files: [])
                pkg.headerSize = sizeBytes
                pkg.headerDate = date
                pkg.headerTime = time
                packageMap[path] = pkg
            } else if entryType == 10 {
                if let pkgName = path.split(separator: "/").first.map(String.init) {
                    var pkg = packageMap[pkgName] ?? CSLRawPackage(name: pkgName, headerSize: 0, headerDate: "", headerTime: "", files: [])
                    pkg.files.append(CSLFileItem(
                        path: path,
                        sizeBytes: sizeBytes,
                        md5: md5,
                        date: date,
                        time: time
                    ))
                    packageMap[pkgName] = pkg
                }
            }
        }
        
        return packageMap.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - CSL Cache Actor

actor CSLCacheActor {
    private var cachedIndex: (timestamp: Date, content: String)?
    private var descCache: [String: String] = [:]
    private var md5Cache: [String: (size: Int64, mtime: TimeInterval, hash: String)] = [:]
    
    func getCachedIndex() -> String? {
        if let cached = cachedIndex, Date().timeIntervalSince(cached.timestamp) < 300 {
            return cached.content
        }
        return nil
    }
    
    func setCachedIndex(_ content: String) {
        cachedIndex = (Date(), content)
    }
    
    func getCachedDescription(for name: String) -> String? {
        descCache[name]
    }
    
    func setCachedDescription(_ desc: String, for name: String) {
        descCache[name] = desc
    }
    
    func getCachedMD5(path: String, size: Int64, mtime: TimeInterval) -> String? {
        if let cached = md5Cache[path], cached.size == size, cached.mtime == mtime {
            return cached.hash
        }
        return nil
    }
    
    func setCachedMD5(hash: String, path: String, size: Int64, mtime: TimeInterval) {
        md5Cache[path] = (size, mtime, hash)
    }
    
    func invalidateMD5(path: String) {
        md5Cache.removeValue(forKey: path)
    }
}

// MARK: - CSL Updater Service

final class CSLUpdaterService: Sendable {
    static let shared = CSLUpdaterService()
    private var fileManager: FileManager { .default }
    private let cache = CSLCacheActor()
    
    static let defaultServerBaseURL = "https://x-csl.ru"
    static let indexRelativePath = "package/x-csl-indexes.idx"
    static let packageBaseRelativePath = "package"
    
    // MARK: - MD5 Hashing with Cache
    
    func computeMD5Cached(for fileURL: URL) async -> String? {
        let path = fileURL.path
        guard let attrs = try? fileManager.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64,
              let modDate = attrs[.modificationDate] as? Date else {
            return nil
        }
        let mtime = modDate.timeIntervalSince1970
        
        if let cached = await cache.getCachedMD5(path: path, size: size, mtime: mtime) {
            return cached
        }
        
        guard let hash = computeFileMD5(fileURL: fileURL) else { return nil }
        await cache.setCachedMD5(hash: hash, path: path, size: size, mtime: mtime)
        return hash
    }
    
    private func computeFileMD5(fileURL: URL) -> String? {
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? fileHandle.close() }
        
        var hasher = Insecure.MD5()
        let bufferSize = 65536 // 64KB
        while true {
            let data = fileHandle.readData(ofLength: bufferSize)
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Remote Index Fetching
    
    func fetchRemoteIndex(serverBaseURL: String = defaultServerBaseURL) async throws -> String {
        if let cached = await cache.getCachedIndex() {
            return cached
        }
        
        let trimmedServer = serverBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let fullURLString = "\(trimmedServer)/\(CSLUpdaterService.indexRelativePath)"
        
        guard let url = URL(string: fullURLString) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("XPlaneLauncher", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        guard let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw URLError(.cannotDecodeContentData)
        }
        
        await cache.setCachedIndex(content)
        return content
    }
    
    // MARK: - Package Description Fetching
    
    func fetchPackageDescription(packageName: String, serverBaseURL: String = defaultServerBaseURL) async -> String? {
        if let cached = await cache.getCachedDescription(for: packageName) {
            return cached
        }
        
        let trimmedServer = serverBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let encodedName = packageName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(trimmedServer)/\(CSLUpdaterService.packageBaseRelativePath)/\(encodedName)/x-csl-info.info") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("XPlaneLauncher", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200,
               let desc = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) {
                let cleanDesc = desc.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces) ?? ""
                let result = cleanDesc.isEmpty ? packageName : cleanDesc
                await cache.setCachedDescription(result, for: packageName)
                return result
            }
        } catch {
            // Ignore description fetch failure
        }
        
        return nil
    }
    
    // MARK: - Package Comparison
    
    func comparePackage(raw: CSLRawPackage, cslBaseFolder: URL) async -> (status: CSLPackageStatus, filesToUpdate: Int, updateSizeBytes: Int64, isInstalled: Bool) {
        let pkgDir = cslBaseFolder.appendingPathComponent(raw.name)
        var isDir: ObjCBool = false
        let isInstalled = fileManager.fileExists(atPath: pkgDir.path, isDirectory: &isDir) && isDir.boolValue
        
        if !isInstalled {
            let totalBytes = raw.files.reduce(Int64(0)) { $0 + $1.sizeBytes }
            return (.notInstalled, raw.files.count, totalBytes, false)
        }
        
        let prefix = "\(raw.name)/"
        var filesToUpdate = 0
        var updateSize: Int64 = 0
        
        for file in raw.files {
            let relPath = file.path.hasPrefix(prefix) ? String(file.path.dropFirst(prefix.count)) : file.path
            let localFileURL = pkgDir.appendingPathComponent(relPath)
            let isObj = localFileURL.pathExtension.lowercased() == "obj"
            let bakFileURL = localFileURL.deletingPathExtension().appendingPathExtension(CSLLightsUpdater.backupExtension)
            let fileToCheck = (isObj && fileManager.fileExists(atPath: bakFileURL.path)) ? bakFileURL : localFileURL
            
            guard fileManager.fileExists(atPath: fileToCheck.path) else {
                filesToUpdate += 1
                updateSize += file.sizeBytes
                continue
            }
            
            guard let attrs = try? fileManager.attributesOfItem(atPath: fileToCheck.path),
                  let localSize = attrs[.size] as? Int64 else {
                filesToUpdate += 1
                updateSize += file.sizeBytes
                continue
            }
            
            if localSize != file.sizeBytes {
                filesToUpdate += 1
                updateSize += file.sizeBytes
                continue
            }
            
            if let expectedMD5 = file.md5, !expectedMD5.isEmpty {
                let localMD5 = await computeMD5Cached(for: fileToCheck)?.lowercased()
                if localMD5 != expectedMD5 {
                    filesToUpdate += 1
                    updateSize += file.sizeBytes
                    continue
                }
            }
        }
        
        let status: CSLPackageStatus = (filesToUpdate == 0) ? .upToDate : .needsUpdate
        return (status, filesToUpdate, updateSize, true)
    }
    
    // MARK: - File Download with Retry & Progress
    
    func downloadPackage(
        package: CSLPackage,
        targetFolder: URL,
        serverBaseURL: String = defaultServerBaseURL,
        onProgress: @Sendable @escaping (Double, Int64, String) -> Void,
        onLog: @Sendable @escaping (String) -> Void,
        isCancelled: @Sendable @escaping () -> Bool
    ) async throws {
        let pkgDir = targetFolder.appendingPathComponent(package.name)
        try fileManager.createDirectory(at: pkgDir, withIntermediateDirectories: true)
        
        let prefix = "\(package.name)/"
        var filesToDownload: [CSLFileItem] = []
        
        for file in package.files {
            let relPath = file.path.hasPrefix(prefix) ? String(file.path.dropFirst(prefix.count)) : file.path
            let localFileURL = pkgDir.appendingPathComponent(relPath)
            let isObj = localFileURL.pathExtension.lowercased() == "obj"
            let bakFileURL = localFileURL.deletingPathExtension().appendingPathExtension(CSLLightsUpdater.backupExtension)
            let fileToCheck = (isObj && fileManager.fileExists(atPath: bakFileURL.path)) ? bakFileURL : localFileURL
            
            if !fileManager.fileExists(atPath: fileToCheck.path) {
                filesToDownload.append(file)
            } else if let attrs = try? fileManager.attributesOfItem(atPath: fileToCheck.path),
                      let size = attrs[.size] as? Int64, size != file.sizeBytes {
                filesToDownload.append(file)
            } else if let expectedMD5 = file.md5, !expectedMD5.isEmpty {
                let localMD5 = await computeMD5Cached(for: fileToCheck)?.lowercased()
                if localMD5 != expectedMD5 {
                    filesToDownload.append(file)
                }
            }
        }
        
        if filesToDownload.isEmpty {
            onProgress(1.0, 0, "Complete")
            return
        }
        
        let totalFiles = filesToDownload.count
        let totalBytes = filesToDownload.reduce(Int64(0)) { $0 + $1.sizeBytes }
        onLog("[CSL] Starting download of \(package.name): \(totalFiles) files (\(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)))")
        
        var downloadedBytes: Int64 = 0
        let trimmedServer = serverBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        for (index, file) in filesToDownload.enumerated() {
            if isCancelled() {
                onLog("[CSL] Download cancelled for \(package.name)")
                throw CancellationError()
            }
            
            let relPath = file.path.hasPrefix(prefix) ? String(file.path.dropFirst(prefix.count)) : file.path
            let localFileURL = pkgDir.appendingPathComponent(relPath)
            let parentDir = localFileURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: parentDir.path) {
                try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }
            
            let displayFileName = (relPath as NSString).lastPathComponent
            onProgress(
                Double(downloadedBytes) / Double(max(totalBytes, 1)),
                downloadedBytes,
                "(\(index + 1)/\(totalFiles)) \(displayFileName)"
            )
            
            // Build escaped URL
            let pathComponents = file.path.split(separator: "/").map {
                $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
            }
            let fullURLString = "\(trimmedServer)/\(CSLUpdaterService.packageBaseRelativePath)/\(pathComponents.joined(separator: "/"))"
            guard let url = URL(string: fullURLString) else {
                onLog("[CSL] Invalid URL for \(file.path)")
                continue
            }
            
            // Download with up to 3 retries
            var success = false
            for attempt in 1...3 {
                if isCancelled() { throw CancellationError() }
                
                do {
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 30
                    request.setValue("XPlaneLauncher", forHTTPHeaderField: "User-Agent")
                    
                    let (tempLocalURL, response) = try await URLSession.shared.download(for: request)
                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        throw URLError(.badServerResponse)
                    }
                    
                    // Atomic move and clean prior .bak
                    let bakURL = localFileURL.deletingPathExtension().appendingPathExtension(CSLLightsUpdater.backupExtension)
                    if fileManager.fileExists(atPath: bakURL.path) {
                        try? fileManager.removeItem(at: bakURL)
                    }
                    if fileManager.fileExists(atPath: localFileURL.path) {
                        try fileManager.removeItem(at: localFileURL)
                    }
                    try fileManager.moveItem(at: tempLocalURL, to: localFileURL)
                    
                    // Invalidate MD5 cache for this file
                    await cache.invalidateMD5(path: localFileURL.path)
                    
                    downloadedBytes += file.sizeBytes
                    success = true
                    break
                } catch {
                    if attempt < 3 {
                        try? await Task.sleep(nanoseconds: UInt64(attempt) * 500_000_000)
                    } else {
                        onLog("[CSL] Failed downloading \(relPath): \(error.localizedDescription)")
                        throw error
                    }
                }
            }
            
            if !success {
                throw URLError(.cannotDecodeRawData)
            }
        }
        
        onProgress(1.0, totalBytes, "Up to date")
        onLog("[CSL] Successfully installed/updated \(package.name)")
    }
}

// MARK: - CSL Manager (Observable State)

@MainActor
@Observable
final class CSLManager {
    private let fileManager = FileManager.default
    private let service = CSLUpdaterService.shared
    private let autoCheckCSLKey = "AutoCheckCSLUpdates"
    
    var automaticallyCheckCSLUpdates: Bool {
        didSet {
            UserDefaults.standard.set(automaticallyCheckCSLUpdates, forKey: autoCheckCSLKey)
        }
    }
    
    var cslFolderURL: URL? {
        didSet {
            if cslFolderURL != oldValue {
                packages = []
                if automaticallyCheckCSLUpdates {
                    scanAndCheck()
                }
            }
        }
    }
    
    var packages: [CSLPackage] = []
    var isChecking: Bool = false
    var isUpdating: Bool = false
    let logger = ConsoleLogger()
    
    private var activeDownloadTasks: [String: Task<Void, Never>] = [:]
    
    init() {
        if UserDefaults.standard.object(forKey: autoCheckCSLKey) == nil {
            self.automaticallyCheckCSLUpdates = true
        } else {
            self.automaticallyCheckCSLUpdates = UserDefaults.standard.bool(forKey: autoCheckCSLKey)
        }
    }
    
    var isProcessing: Bool {
        isChecking || isUpdating || packages.contains { $0.status == .checking || $0.status == .updating }
    }
    
    var updatesAvailableCount: Int {
        packages.filter { $0.isInstalled && $0.status == .needsUpdate }.count
    }
    
    var installedCount: Int {
        packages.filter { $0.isInstalled }.count
    }
    
    func log(_ message: String) {
        logger.log(message)
    }
    
    func clearLogs() {
        logger.clear()
    }
    
    // MARK: - Scanning & Update Checking
    
    func scanAndCheck() {
        guard let folderURL = cslFolderURL else {
            packages = []
            return
        }
        
        guard !isChecking else { return }
        isChecking = true
        log("[CSL] Checking X-CSL packages index...")
        
        Task { @MainActor in
            do {
                let indexContent = try await service.fetchRemoteIndex()
                let rawPackages = CSLIndexParser.parseIndex(content: indexContent)
                
                log("[CSL] Remote index loaded: \(rawPackages.count) total packages available")
                
                var parsedPackages: [CSLPackage] = []
                for raw in rawPackages {
                    let comparison = await service.comparePackage(raw: raw, cslBaseFolder: folderURL)
                    
                    let statusMsg: String
                    switch comparison.status {
                    case .upToDate:
                        statusMsg = "Up to date"
                    case .needsUpdate:
                        statusMsg = "Update available (\(comparison.filesToUpdate) files, \(ByteCountFormatter.string(fromByteCount: comparison.updateSizeBytes, countStyle: .file)))"
                    case .notInstalled:
                        statusMsg = "Not installed"
                    case .checking:
                        statusMsg = "Checking..."
                    case .updating:
                        statusMsg = "Updating..."
                    case .error:
                        statusMsg = "Error"
                    }
                    
                    let headerDate = !raw.headerDate.isEmpty ? "\(raw.headerDate) \(raw.headerTime)" : ""
                    let totalSize = raw.headerSize > 0 ? raw.headerSize : raw.files.reduce(0) { $0 + $1.sizeBytes }
                    
                    let pkg = CSLPackage(
                        name: raw.name,
                        title: raw.name,
                        totalSizeBytes: totalSize,
                        fileCount: raw.files.count,
                        status: comparison.status,
                        filesToUpdate: comparison.filesToUpdate,
                        updateSizeBytes: comparison.updateSizeBytes,
                        lastUpdated: headerDate,
                        statusMessage: statusMsg,
                        isInstalled: comparison.isInstalled,
                        files: raw.files
                    )
                    parsedPackages.append(pkg)
                }
                
                self.packages = parsedPackages
                self.isChecking = false
                
                let needUpdate = self.updatesAvailableCount
                let installed = self.installedCount
                self.log("[CSL] Scan complete: \(installed) installed, \(needUpdate) update(s) available")
                
                // Fetch descriptions in background for installed or top packages
                self.fetchDescriptionsInBackground()
            } catch {
                self.isChecking = false
                self.log("[CSL] Error fetching index: \(error.localizedDescription)")
            }
        }
    }
    
    private func fetchDescriptionsInBackground() {
        Task { @MainActor in
            for i in 0..<packages.count {
                let name = packages[i].name
                if let desc = await service.fetchPackageDescription(packageName: name), !desc.isEmpty {
                    if i < packages.count && packages[i].name == name {
                        packages[i].title = desc
                    }
                }
            }
        }
    }
    
    // MARK: - Package Actions
    
    func updatePackage(_ package: CSLPackage) {
        guard let folderURL = cslFolderURL else {
            log("[CSL] Cannot update: CSL folder not set")
            return
        }
        
        guard let index = packages.firstIndex(where: { $0.id == package.id }) else { return }
        packages[index].status = .updating
        packages[index].statusMessage = "Starting download..."
        packages[index].downloadProgress = 0.0
        
        let pkgToUpdate = packages[index]
        let pkgName = pkgToUpdate.name
        
        let task = Task { @MainActor in
            do {
                try await service.downloadPackage(
                    package: pkgToUpdate,
                    targetFolder: folderURL,
                    onProgress: { [weak self] progress, bytes, currentFile in
                        Task { @MainActor in
                            guard let self = self, let i = self.packages.firstIndex(where: { $0.name == pkgName }) else { return }
                            self.packages[i].downloadProgress = progress
                            self.packages[i].downloadedBytes = bytes
                            self.packages[i].currentDownloadFile = currentFile
                            self.packages[i].statusMessage = "Downloading \(currentFile)"
                        }
                    },
                    onLog: { [weak self] msg in
                        Task { @MainActor in
                            self?.log(msg)
                        }
                    },
                    isCancelled: {
                        Task.isCancelled
                    }
                )
                
                if let i = self.packages.firstIndex(where: { $0.name == pkgName }) {
                    self.packages[i].status = .upToDate
                    self.packages[i].isInstalled = true
                    self.packages[i].filesToUpdate = 0
                    self.packages[i].updateSizeBytes = 0
                    self.packages[i].downloadProgress = 1.0
                    self.packages[i].statusMessage = "Up to date"
                }
                
                // If XP12 lighting is enabled, apply it automatically to the newly updated package
                if UserDefaults.standard.bool(forKey: "EnableCSLXP12Lights") {
                    let pkgDir = folderURL.appendingPathComponent(pkgName)
                    CSLLightsUpdater.shared.processPackage(packageURL: pkgDir, flashingBeacons: true) { [weak self] msg in
                        Task { @MainActor in
                            self?.log(msg)
                        }
                    }
                }
                
                self.activeDownloadTasks.removeValue(forKey: pkgName)
                self.isUpdating = !self.activeDownloadTasks.isEmpty
            } catch is CancellationError {
                if let i = self.packages.firstIndex(where: { $0.name == pkgName }) {
                    self.packages[i].status = self.packages[i].isInstalled ? .needsUpdate : .notInstalled
                    self.packages[i].statusMessage = "Cancelled"
                }
                self.activeDownloadTasks.removeValue(forKey: pkgName)
                self.isUpdating = !self.activeDownloadTasks.isEmpty
            } catch {
                if let i = self.packages.firstIndex(where: { $0.name == pkgName }) {
                    self.packages[i].status = .error
                    self.packages[i].statusMessage = "Update failed: \(error.localizedDescription)"
                }
                self.log("[CSL] Update failed for \(pkgName): \(error.localizedDescription)")
                self.activeDownloadTasks.removeValue(forKey: pkgName)
                self.isUpdating = !self.activeDownloadTasks.isEmpty
            }
        }
        
        activeDownloadTasks[pkgName] = task
        isUpdating = true
    }
    
    func cancelUpdate(_ package: CSLPackage) {
        if let task = activeDownloadTasks[package.name] {
            task.cancel()
            activeDownloadTasks.removeValue(forKey: package.name)
        }
        if let i = packages.firstIndex(where: { $0.id == package.id }) {
            packages[i].status = packages[i].isInstalled ? .needsUpdate : .notInstalled
            packages[i].statusMessage = "Cancelled"
            packages[i].downloadProgress = 0.0
        }
        isUpdating = !activeDownloadTasks.isEmpty
    }
    
    func updateAll() {
        let toUpdate = packages.filter { $0.isInstalled && $0.status == .needsUpdate }
        guard !toUpdate.isEmpty else { return }
        log("[CSL] Starting Update All for \(toUpdate.count) packages")
        for pkg in toUpdate {
            updatePackage(pkg)
        }
    }
    
    func verifyPackage(_ package: CSLPackage) {
        guard let folderURL = cslFolderURL else { return }
        guard let index = packages.firstIndex(where: { $0.id == package.id }) else { return }
        
        packages[index].status = .checking
        packages[index].statusMessage = "Verifying files..."
        
        let pkg = packages[index]
        Task { @MainActor in
            let raw = CSLRawPackage(
                name: pkg.name,
                headerSize: pkg.totalSizeBytes,
                headerDate: "",
                headerTime: "",
                files: pkg.files
            )
            let result = await service.comparePackage(raw: raw, cslBaseFolder: folderURL)
            if let i = self.packages.firstIndex(where: { $0.id == pkg.id }) {
                self.packages[i].status = result.status
                self.packages[i].isInstalled = result.isInstalled
                self.packages[i].filesToUpdate = result.filesToUpdate
                self.packages[i].updateSizeBytes = result.updateSizeBytes
                self.packages[i].statusMessage = (result.status == .upToDate) ? "Up to date" : "Update available (\(result.filesToUpdate) files)"
            }
        }
    }
    
    // MARK: - XP12 Lighting Batch Operations
    
    var isApplyingLights: Bool = false
    
    func applyXP12LightsToAll(flashingBeacons: Bool = true) {
        guard let folderURL = cslFolderURL else { return }
        guard !isApplyingLights else { return }
        isApplyingLights = true
        log("[XP12 Lights] Applying modern X-Plane 12 lighting to all installed CSL models...")
        
        Task { @MainActor in
            let installedPackages = self.packages.filter { $0.isInstalled }
            for pkg in installedPackages {
                let pkgDir = folderURL.appendingPathComponent(pkg.name)
                CSLLightsUpdater.shared.processPackage(packageURL: pkgDir, flashingBeacons: flashingBeacons) { [weak self] msg in
                    Task { @MainActor in
                        self?.log(msg)
                    }
                }
            }
            self.isApplyingLights = false
            self.log("[XP12 Lights] Finished applying X-Plane 12 lighting to \(installedPackages.count) packages")
            self.scanAndCheck()
        }
    }
    
    func revertXP12LightsFromAll() {
        guard let folderURL = cslFolderURL else { return }
        guard !isApplyingLights else { return }
        isApplyingLights = true
        log("[XP12 Lights] Reverting all CSL models to original unmodified lighting...")
        
        Task { @MainActor in
            let installedPackages = self.packages.filter { $0.isInstalled }
            for pkg in installedPackages {
                let pkgDir = folderURL.appendingPathComponent(pkg.name)
                CSLLightsUpdater.shared.revertPackage(packageURL: pkgDir) { [weak self] msg in
                    Task { @MainActor in
                        self?.log(msg)
                    }
                }
            }
            self.isApplyingLights = false
            self.log("[XP12 Lights] Finished reverting X-Plane 12 lighting on \(installedPackages.count) packages")
            self.scanAndCheck()
        }
    }
}
