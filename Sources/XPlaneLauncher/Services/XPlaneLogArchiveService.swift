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
public final class XPlaneLogArchiveService {
    public static let shared = XPlaneLogArchiveService()

    private let pathService = PathService.shared
    private let parser = XPlaneLogParser.shared
    private let engine = XPlaneLogDiagnosticsEngine.shared

    public var availableLogFiles: [LogFileItem] = []
    public var selectedLogFile: LogFileItem? = nil
    public var currentReport: LogAnalysisReport? = nil
    public var isLoading: Bool = false
    public var errorMessage: String? = nil

    public init() {}

    public func discoverLogFiles(for xPlanePath: URL?) {
        var files: [LogFileItem] = []
        let fm = FileManager.default

        guard let xPlanePath = xPlanePath else {
            self.availableLogFiles = []
            return
        }

        // 1. Check current Log.txt
        let currentLogURL = pathService.logTxtURL(for: xPlanePath)
        if fm.fileExists(atPath: currentLogURL.path) {
            let attrs = try? fm.attributesOfItem(atPath: currentLogURL.path)
            let modDate = attrs?[.modificationDate] as? Date
            let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0

            let currentItem = LogFileItem(
                url: currentLogURL,
                displayName: "Current Session (Log.txt)",
                sourceType: .current,
                modificationDate: modDate,
                fileSize: size
            )
            files.append(currentItem)
        }

        // 2. Scan Output/Log Archive/
        let archiveDir = pathService.logArchiveFolder(for: xPlanePath)
        if fm.fileExists(atPath: archiveDir.path),
           let contents = try? fm.contentsOfDirectory(at: archiveDir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: .skipsHiddenFiles) {
            let txtArchives = contents.filter { $0.pathExtension.lowercased() == "txt" }
            for archiveURL in txtArchives {
                let attrs = try? fm.attributesOfItem(atPath: archiveURL.path)
                let modDate = attrs?[.modificationDate] as? Date
                let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0

                let item = LogFileItem(
                    url: archiveURL,
                    displayName: archiveURL.deletingPathExtension().lastPathComponent,
                    sourceType: .archive,
                    modificationDate: modDate,
                    fileSize: size
                )
                files.append(item)
            }
        }

        // Sort archives: Current log first, then archives sorted by modification date descending
        self.availableLogFiles = files.sorted { first, second in
            if first.sourceType == .current { return true }
            if second.sourceType == .current { return false }
            return (first.modificationDate ?? Date.distantPast) > (second.modificationDate ?? Date.distantPast)
        }

        // Auto-select first item if none selected or if previous selection is no longer available
        if selectedLogFile == nil || !availableLogFiles.contains(where: { $0.url == selectedLogFile?.url }) {
            if let first = availableLogFiles.first {
                selectAndAnalyze(first)
            }
        }
    }

    public func selectAndAnalyze(_ item: LogFileItem) {
        self.selectedLogFile = item
        self.isLoading = true
        self.errorMessage = nil

        Task.detached(priority: .userInitiated) { [weak self, item, parser = self.parser, engine = self.engine] in
            do {
                let entries = try parser.parseFile(at: item.url)
                let report = engine.analyze(entries: entries, fileItem: item)

                await MainActor.run {
                    guard let self = self, self.selectedLogFile?.url == item.url else { return }
                    self.currentReport = report
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    guard let self = self, self.selectedLogFile?.url == item.url else { return }
                    self.errorMessage = "Failed to parse log file: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }

    public func importExternalFile(url: URL) {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let modDate = attrs?[.modificationDate] as? Date
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0

        let item = LogFileItem(
            url: url,
            displayName: url.lastPathComponent,
            sourceType: .custom,
            modificationDate: modDate,
            fileSize: size
        )

        // Insert at beginning of archives or select directly
        if !availableLogFiles.contains(where: { $0.url == url }) {
            availableLogFiles.insert(item, at: availableLogFiles.count > 0 && availableLogFiles[0].sourceType == .current ? 1 : 0)
        }

        selectAndAnalyze(item)
    }

    public func refresh() {
        if let current = selectedLogFile {
            selectAndAnalyze(current)
        }
    }
}
