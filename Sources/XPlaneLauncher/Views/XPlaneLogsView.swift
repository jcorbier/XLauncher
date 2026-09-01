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

import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct XPlaneLogsView: View {
    @Environment(PluginManager.self) private var pluginManager
    @State private var logService = XPlaneLogArchiveService.shared
    @State private var selectedTab: LogTab = .overview
    @State private var isShowingFileImporter: Bool = false
    @State private var isShowingExportPicker: Bool = false
    @State private var searchText: String = ""
    @State private var hasCopiedReport: Bool = false
    @State private var exportContent: String = ""

    public init() {}

    public enum LogTab: String, CaseIterable, Identifiable, Sendable {
        case overview = "Overview"
        case crash = "Crash"
        case errors = "Errors & Warnings"
        case scenery = "Missing Scenery"
        case scripts = "Lua & SASL"
        case performance = "Startup Times"
        case rawLog = "Raw Log"

        public var id: String { rawValue }

        public var systemImage: String {
            switch self {
            case .overview: return "waveform.path.ecg"
            case .crash: return "exclamationmark.octagon.fill"
            case .errors: return "exclamationmark.triangle.fill"
            case .scenery: return "map.fill"
            case .scripts: return "scroll.fill"
            case .performance: return "gauge.with.needle.fill"
            case .rawLog: return "doc.text.magnifyingglass"
            }
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerToolbar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Material.bar)

            Divider()

            if logService.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Analyzing X-Plane Log...")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = logService.errorMessage {
                ContentUnavailableView {
                    Label("Log Analysis Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") {
                        logService.refresh()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let report = logService.currentReport {
                VStack(spacing: 0) {
                    // Session Status Card
                    statusBanner(report: report)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    // Tab Picker
                    tabSelector(report: report)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)

                    Divider()

                    // Tab Content
                    Group {
                        switch selectedTab {
                        case .overview:
                            OverviewTabView(report: report, onSelectTab: { selectedTab = $0 })
                        case .crash:
                            CrashTabView(report: report)
                        case .errors:
                            ErrorsTabView(report: report, searchText: $searchText)
                        case .scenery:
                            MissingSceneryTabView(report: report)
                        case .scripts:
                            ScriptsTabView(report: report)
                        case .performance:
                            StartupPerformanceTabView(report: report)
                        case .rawLog:
                            RawLogTabView(report: report, searchText: $searchText)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ContentUnavailableView {
                    Label("No X-Plane Log Available", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text("No Log.txt or archive sessions found in your X-Plane directory.")
                } actions: {
                    Button("Open External Log File...") {
                        isShowingFileImporter = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            logService.discoverLogFiles(for: pluginManager.xPlanePath)
        }
        .onChange(of: pluginManager.xPlanePath) { _, newPath in
            logService.discoverLogFiles(for: newPath)
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.plainText, .text, .data, .item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    logService.importExternalFile(url: url)
                }
            case .failure:
                break
            }
        }
    }

    // MARK: - Header Toolbar

    private var headerToolbar: some View {
        HStack(spacing: 12) {
            // Log File Picker Menu
            Menu {
                if !logService.availableLogFiles.isEmpty {
                    Section("Discovered Logs") {
                        ForEach(logService.availableLogFiles) { fileItem in
                            Button {
                                logService.selectAndAnalyze(fileItem)
                            } label: {
                                HStack {
                                    Text(fileItem.displayName)
                                    if logService.selectedLogFile?.url == fileItem.url {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                    Divider()
                }

                Button("Open External Log File...") {
                    isShowingFileImporter = true
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.tint)
                    Text(logService.selectedLogFile?.displayName ?? "Select Log File")
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .menuStyle(.borderedButton)

            if let selected = logService.selectedLogFile {
                Text(selected.formattedSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let date = selected.modificationDate {
                    Text("•")
                        .foregroundStyle(.tertiary)
                    Text(date.formatted(date: .abbreviated, time: .standard))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Action Buttons
            Button {
                logService.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Reload & Re-analyze Log")

            if let report = logService.currentReport {
                Button {
                    copyReportToClipboard(report: report)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: hasCopiedReport ? "checkmark" : "doc.on.doc")
                        Text(hasCopiedReport ? "Copied" : "Copy Report")
                    }
                }
                .foregroundStyle(hasCopiedReport ? Color.green : Color.primary)
                .help("Copy Markdown Diagnostics Report to Clipboard")

                if let url = logService.selectedLogFile?.url {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help("Reveal Log File in Finder")
                }
            }
        }
    }

    // MARK: - Status Banner

    private func statusBanner(report: LogAnalysisReport) -> some View {
        HStack(spacing: 16) {
            // Status Indicator Pill
            HStack(spacing: 8) {
                Image(systemName: report.status.systemImage)
                    .font(.title3)
                    .foregroundStyle(statusColor(for: report.status))

                VStack(alignment: .leading, spacing: 2) {
                    Text(report.status.title)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(statusColor(for: report.status))

                    if let crash = report.crashDiagnostic {
                        Text(crash.offendingPluginOrSubsystem.map { "Fault in \($0)" } ?? crash.signalOrReason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if case .abnormalTermination(let reason) = report.status {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("\(report.lineCount) lines parsed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(statusColor(for: report.status).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Spacer()

            // Summary Metric Pills
            HStack(spacing: 12) {
                metricItem(
                    title: "Errors",
                    value: "\(report.errorCount)",
                    color: report.errorCount > 0 ? .red : .secondary,
                    icon: "xmark.octagon.fill"
                )

                metricItem(
                    title: "Warnings",
                    value: "\(report.warningCount)",
                    color: report.warningCount > 0 ? .orange : .secondary,
                    icon: "exclamationmark.triangle.fill"
                )

                metricItem(
                    title: "Missing Scenery",
                    value: "\(report.missingSceneryCount)",
                    color: report.missingSceneryCount > 0 ? .yellow : .secondary,
                    icon: "map.fill"
                )

                metricItem(
                    title: "Script Errors",
                    value: "\(report.scriptErrorCount)",
                    color: report.scriptErrorCount > 0 ? .purple : .secondary,
                    icon: "scroll.fill"
                )

                if let startup = report.totalStartupSeconds {
                    metricItem(
                        title: "Startup Time",
                        value: String(format: "%.1f s", startup),
                        color: .blue,
                        icon: "timer"
                    )
                }
            }
        }
    }

    private func metricItem(title: String, value: String, color: Color, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func statusColor(for status: LogSessionStatus) -> Color {
        switch status {
        case .cleanExit: return .green
        case .crashed: return .red
        case .abnormalTermination: return .orange
        case .runningOrIncomplete: return .blue
        }
    }

    // MARK: - Tab Selector

    private func tabSelector(report: LogAnalysisReport) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(LogTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.systemImage)
                            Text(tab.rawValue)

                            // Tab Badges
                            if tab == .crash, report.crashDiagnostic != nil {
                                Text("!")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.red)
                                    .clipShape(Capsule())
                            } else if tab == .errors && report.errorCount > 0 {
                                Text("\(report.errorCount)")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.red)
                                    .clipShape(Capsule())
                            } else if tab == .scenery && report.missingSceneryCount > 0 {
                                Text("\(report.missingSceneryCount)")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.orange)
                                    .clipShape(Capsule())
                            } else if tab == .scripts && report.scriptErrorCount > 0 {
                                Text("\(report.scriptErrorCount)")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.purple)
                                    .clipShape(Capsule())
                            }
                        }
                        .font(.caption)
                        .fontWeight(selectedTab == tab ? .semibold : .regular)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                        .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func copyReportToClipboard(report: LogAnalysisReport) {
        let md = report.generateMarkdownReport()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)

        withAnimation {
            hasCopiedReport = true
        }

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                withAnimation {
                    hasCopiedReport = false
                }
            }
        }
    }
}

// MARK: - Overview Tab View

private struct OverviewTabView: View {
    let report: LogAnalysisReport
    let onSelectTab: (XPlaneLogsView.LogTab) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Crash Alert Banner (if crashed)
                if let crash = report.crashDiagnostic {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.octagon.fill")
                                .foregroundStyle(.red)
                                .font(.title3)
                            Text("Crash Root Cause Detected")
                                .font(.headline)
                                .foregroundStyle(.red)
                            Spacer()
                            Button("View Stack Backtrace") {
                                onSelectTab(.crash)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .controlSize(.small)
                        }

                        if let plugin = crash.offendingPluginOrSubsystem {
                            Text("Offending Plugin / Subsystem: **\(plugin)**")
                                .font(.subheadline)
                        }

                        Text(crash.signalOrReason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                    )
                }

                // Missing Scenery Summary Card
                if !report.missingSceneryIssues.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Missing Scenery Objects & Packages (\(report.missingSceneryCount))", systemImage: "map.fill")
                                .font(.headline)
                                .foregroundStyle(.orange)
                            Spacer()
                            Button("View All") {
                                onSelectTab(.scenery)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        Text("X-Plane failed to locate objects referenced in your scenery. Grouped by package / library namespace:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        VStack(spacing: 4) {
                            ForEach(Array(report.missingSceneryByPackage.keys.sorted().prefix(5)), id: \.self) { pkg in
                                HStack {
                                    Image(systemName: "folder.badge.minus")
                                        .foregroundStyle(.orange)
                                    Text(pkg)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text("\(report.missingSceneryByPackage[pkg]?.count ?? 0) missing")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(NSColor.controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(NSColor.windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
                }

                // Script Errors Summary Card
                if !report.scriptErrors.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("FlyWithLua & SASL Script Errors (\(report.scriptErrorCount))", systemImage: "scroll.fill")
                                .font(.headline)
                                .foregroundStyle(.purple)
                            Spacer()
                            Button("View Scripts") {
                                onSelectTab(.scripts)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        VStack(spacing: 4) {
                            ForEach(report.scriptErrors.prefix(4)) { err in
                                HStack {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .foregroundStyle(.purple)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("[\(err.engine.rawValue)] \(err.scriptOrModuleName)")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                        Text(err.errorMessage)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text("Line \(err.lineNumber)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(NSColor.controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(NSColor.windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                    )
                }

                // Slowest Plugins Summary Card
                if !report.startupTimings.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Slowest Startup Components", systemImage: "gauge.with.needle.fill")
                                .font(.headline)
                                .foregroundStyle(.blue)
                            Spacer()
                            Button("View Full Breakdown") {
                                onSelectTab(.performance)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        let slowest = report.startupTimings.sorted(by: { $0.durationSeconds > $1.durationSeconds }).prefix(5)
                        VStack(spacing: 4) {
                            ForEach(slowest) { item in
                                HStack {
                                    Image(systemName: item.category == .plugin ? "puzzlepiece.extension" : "map")
                                        .foregroundStyle(.blue)
                                    Text(item.name)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text(item.formattedDuration)
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.primary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(NSColor.controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(NSColor.windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
                }

                // Clean session message if no errors found
                if report.crashDiagnostic == nil && report.missingSceneryIssues.isEmpty && report.scriptErrors.isEmpty && report.errorCount == 0 {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.green)
                        Text("No Critical Diagnostics or Crashes Detected")
                            .font(.headline)
                        Text("This flight session concluded normally without plugin aborts, missing scenery objects, or script crashes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(32)
                    .background(Color.green.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Crash Tab View

private struct CrashTabView: View {
    let report: LogAnalysisReport

    var body: some View {
        if let crash = report.crashDiagnostic {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.octagon.fill")
                                .font(.title2)
                                .foregroundStyle(.red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Fatal Crash: \(crash.category.rawValue)")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.red)
                                if let line = crash.crashLineNumber {
                                    Text("Logged at Line #\(line)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }

                        if let plugin = crash.offendingPluginOrSubsystem {
                            HStack(spacing: 6) {
                                Text("Identified Offender:")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(plugin)
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.primary)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }

                        Text(crash.signalOrReason)
                            .font(.body)
                            .padding(.top, 4)
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    if !crash.backtrace.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Stack Backtrace")
                                    .font(.headline)
                                Spacer()
                                Button("Copy Stack Trace") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(crash.backtrace.joined(separator: "\n"), forType: .string)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(crash.backtrace.enumerated()), id: \.offset) { index, frame in
                                    Text(frame)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(frame.contains(".xpl") ? Color.orange : Color.primary)
                                        .textSelection(.enabled)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .padding(16)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(16)
            }
        } else {
            ContentUnavailableView("No Crash Detected", systemImage: "checkmark.circle", description: Text("No fatal crash signatures were detected in this log."))
        }
    }
}

// MARK: - Errors & Warnings Tab View

private struct ErrorsTabView: View {
    let report: LogAnalysisReport
    @Binding var searchText: String
    @State private var filterLevel: XPlaneLogLevel? = nil

    private var filtered: [XPlaneLogEntry] {
        let entries = (report.errorEntries + report.warningEntries).sorted(by: { $0.lineNumber < $1.lineNumber })
        return entries.filter { entry in
            let matchesLevel = filterLevel == nil || entry.level == filterLevel
            let matchesSearch = searchText.isEmpty || entry.message.localizedCaseInsensitiveContains(searchText) || entry.rawLine.localizedCaseInsensitiveContains(searchText)
            return matchesLevel && matchesSearch
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack(spacing: 8) {
                Picker("Severity", selection: $filterLevel) {
                    Text("All Severities").tag(Optional<XPlaneLogLevel>.none)
                    Text("Errors Only (\(report.errorCount))").tag(Optional(XPlaneLogLevel.error))
                    Text("Warnings Only (\(report.warningCount))").tag(Optional(XPlaneLogLevel.warn))
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("Search errors...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .frame(width: 140)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            if filtered.isEmpty {
                ContentUnavailableView("No Matching Entries", systemImage: "line.3.horizontal.decrease.circle")
            } else {
                List(filtered) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Text("L\(entry.lineNumber)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .leading)

                        Text(entry.level.rawValue)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(entry.level == .error || entry.level == .fatal ? Color.red : Color.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 3))

                        Text(entry.message)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(entry.level == .error || entry.level == .fatal ? Color.red : Color.primary)
                            .textSelection(.enabled)

                        Spacer()

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(entry.rawLine, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .help("Copy Line")
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
            }
        }
    }
}

// MARK: - Missing Scenery Tab View

private struct MissingSceneryTabView: View {
    let report: LogAnalysisReport
    @State private var selectedPackage: String? = nil
    @State private var searchSceneryText: String = ""

    private var packages: [String] {
        report.missingSceneryByPackage.keys.sorted()
    }

    private var currentIssues: [MissingSceneryIssue] {
        if let pkg = selectedPackage {
            let issues = report.missingSceneryByPackage[pkg] ?? []
            if searchSceneryText.isEmpty {
                return issues
            } else {
                return issues.filter { $0.assetPath.localizedCaseInsensitiveContains(searchSceneryText) }
            }
        } else {
            let all = report.missingSceneryIssues
            if searchSceneryText.isEmpty {
                return all
            } else {
                return all.filter { $0.assetPath.localizedCaseInsensitiveContains(searchSceneryText) || $0.inferredPackageOrLibrary.localizedCaseInsensitiveContains(searchSceneryText) }
            }
        }
    }

    var body: some View {
        if report.missingSceneryIssues.isEmpty {
            ContentUnavailableView("No Missing Scenery Objects", systemImage: "map", description: Text("No missing scenery assets or DSF loading errors were reported."))
        } else {
            HSplitView {
                // Package / Library Sidebar
                List(selection: $selectedPackage) {
                    Text("All Packages (\(report.missingSceneryCount))")
                        .tag(Optional<String>.none)

                    Section("Inferred Packages / Libraries") {
                        ForEach(packages, id: \.self) { pkg in
                            HStack {
                                Text(pkg)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(report.missingSceneryByPackage[pkg]?.count ?? 0)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(Optional(pkg))
                        }
                    }
                }
                .listStyle(.sidebar)
                .frame(minWidth: 200, maxWidth: 280)

                // Issues List
                VStack(spacing: 0) {
                    HStack {
                        Text(selectedPackage ?? "All Missing Assets")
                            .font(.headline)
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "magnifyingglass")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            TextField("Filter assets...", text: $searchSceneryText)
                                .textFieldStyle(.plain)
                                .font(.caption)
                                .frame(width: 140)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(NSColor.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    Divider()

                    List(currentIssues) { issue in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(issue.assetType.rawValue)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.orange)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))

                                Text("Line \(issue.lineNumber)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                if let pack = issue.referencedBySceneryPack {
                                    Text("• in pack \(pack)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(issue.assetPath, forType: .string)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption2)
                                }
                                .buttonStyle(.plain)
                                .help("Copy Path")
                            }

                            Text(issue.assetPath)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.inset)
                }
            }
        }
    }
}

// MARK: - Scripts Tab View

private struct ScriptsTabView: View {
    let report: LogAnalysisReport

    var body: some View {
        if report.scriptErrors.isEmpty {
            ContentUnavailableView("No Script Errors", systemImage: "scroll", description: Text("No FlyWithLua runtime errors or SASL avionics errors detected."))
        } else {
            List(report.scriptErrors) { err in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(err.engine.rawValue)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(err.engine == .flyWithLua ? Color.purple : Color.teal)
                            .clipShape(Capsule())

                        Text(err.scriptOrModuleName)
                            .font(.headline)
                            .fontWeight(.bold)

                        Spacer()

                        Text("Line \(err.lineNumber)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(err.errorMessage)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)

                    if !err.stackTrace.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Traceback:")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                            ForEach(Array(err.stackTrace.enumerated()), id: \.offset) { _, frame in
                                Text(frame)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.vertical, 4)
            }
            .listStyle(.plain)
            .padding(16)
        }
    }
}

// MARK: - Startup Performance Tab View

private struct StartupPerformanceTabView: View {
    let report: LogAnalysisReport

    private var maxDuration: Double {
        report.startupTimings.map(\.durationSeconds).max() ?? 1.0
    }

    var body: some View {
        if report.startupTimings.isEmpty {
            ContentUnavailableView("No Timing Data", systemImage: "gauge.with.needle", description: Text("No plugin or scenery load timing benchmarks found."))
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if let total = report.totalStartupSeconds {
                    HStack {
                        Label("Total Startup Duration: **\(String(format: "%.2f s", total))**", systemImage: "timer")
                            .font(.headline)
                        Spacer()
                        Text("\(report.startupTimings.count) tracked load events")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(Material.bar)

                    Divider()
                }

                List(report.startupTimings.sorted(by: { $0.durationSeconds > $1.durationSeconds })) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.category == .plugin ? "puzzlepiece.extension" : "map")
                            .font(.title3)
                            .foregroundStyle(item.category == .plugin ? Color.blue : Color.green)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.name)
                                    .font(.body)
                                    .fontWeight(.medium)
                                Spacer()
                                Text(item.formattedDuration)
                                    .font(.body)
                                    .fontWeight(.bold)
                                    .foregroundStyle(item.durationSeconds > 2.0 ? Color.orange : Color.primary)
                            }

                            // Visual Duration Bar
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.secondary.opacity(0.15))
                                        .frame(height: 6)

                                    let ratio = CGFloat(min(1.0, max(0.02, item.durationSeconds / max(maxDuration, 0.001))))
                                    Capsule()
                                        .fill(item.durationSeconds > 3.0 ? Color.red : (item.durationSeconds > 1.0 ? Color.orange : Color.blue))
                                        .frame(width: geo.size.width * ratio, height: 6)
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .listStyle(.inset)
            }
        }
    }
}

// MARK: - Raw Log Tab View

private struct RawLogTabView: View {
    let report: LogAnalysisReport
    @Binding var searchText: String

    private var filtered: [XPlaneLogEntry] {
        if searchText.isEmpty {
            return report.allEntries
        } else {
            return report.allEntries.filter { $0.rawLine.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(filtered.count) Lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("Search log...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .frame(width: 180)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            List(filtered) { entry in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(entry.lineNumber)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 45, alignment: .trailing)

                    if let ts = entry.timestampString {
                        Text(ts)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .leading)
                    }

                    Text(entry.rawLine)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(entryColor(for: entry))
                        .textSelection(.enabled)
                }
                .padding(.vertical, 1)
            }
            .listStyle(.plain)
        }
    }

    private func entryColor(for entry: XPlaneLogEntry) -> Color {
        switch entry.level {
        case .fatal, .error: return .red
        case .warn: return .orange
        case .info: return .primary
        }
    }
}
