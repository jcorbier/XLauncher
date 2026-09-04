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

struct DiagnosticsView: View {
    @Environment(PluginManager.self) var pluginManager
    @State private var selectedMode: DiagnosticsMode
    @State private var selectedFilter: FilterCategory = .all
    @State private var searchText: String = ""

    enum DiagnosticsMode: String, CaseIterable, Identifiable {
        case addonHealth = "Add-on Health"
        case xplaneLogs = "X-Plane Logs"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .addonHealth: return "cross.case"
            case .xplaneLogs: return "doc.text.magnifyingglass"
            }
        }
    }

    init(initialMode: DiagnosticsMode = .addonHealth) {
        _selectedMode = State(initialValue: initialMode)
    }

    enum FilterCategory: String, CaseIterable, Identifiable {
        case all = "All Issues"
        case conflicts = "Conflicts"
        case libraries = "Libraries"
        case integrity = "Integrity & Arch"

        var id: String { rawValue }
    }

    private var report: DiagnosticsReport? {
        pluginManager.diagnosticsReport
    }

    private var filteredIssues: [DiagnosticIssue] {
        guard let report = report else { return [] }
        var list = report.issues

        switch selectedFilter {
        case .all:
            break
        case .conflicts:
            list = list.filter { $0.category == .sceneryConflict }
        case .libraries:
            list = list.filter { $0.category == .missingLibrary }
        case .integrity:
            list = list.filter { $0.category == .addonIntegrity || $0.category == .compatibility }
        }

        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            let query = searchText.lowercased()
            list = list.filter {
                $0.title.lowercased().contains(query) ||
                $0.message.lowercased().contains(query) ||
                $0.affectedAddonNames.contains { $0.lowercased().contains(query) }
            }
        }

        return list.sorted { a, b in
            if a.severity != b.severity {
                return a.severity > b.severity // Critical first
            }
            return a.title < b.title
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Diagnostics Sub-View Mode Switcher
            HStack {
                Picker("Diagnostics Mode", selection: $selectedMode) {
                    ForEach(DiagnosticsMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.systemImage)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 340)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            switch selectedMode {
            case .addonHealth:
                addonHealthView
            case .xplaneLogs:
                XPlaneLogsView()
            }
        }
    }

    @ViewBuilder
    private var addonHealthView: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Add-on & Scenery Diagnostics")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Detect duplicate airports, missing object libraries, broken symlinks, and Apple Silicon compatibility.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: {
                    pluginManager.runDiagnostics()
                }) {
                    HStack(spacing: 6) {
                        if pluginManager.isRunningDiagnostics {
                            ProgressView()
                                .controlSize(.small)
                            Text("Analyzing...")
                        } else {
                            Image(systemName: "arrow.clockwise")
                            Text("Run Diagnostics")
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
                .disabled(pluginManager.isRunningDiagnostics || pluginManager.xPlanePath == nil)
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if let report = report {
                // Status Summary Banner
                statusBanner(for: report)

                // Toolbar / Filter Row
                HStack(spacing: 12) {
                    Picker("Filter", selection: $selectedFilter) {
                        ForEach(FilterCategory.allCases) { filter in
                            let count = issueCount(for: filter, in: report)
                            Text("\(filter.rawValue) (\(count))").tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 420)

                    Spacer()

                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search issues...", text: $searchText)
                            .textFieldStyle(.plain)
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                    )
                    .frame(width: 220)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(NSColor.windowBackgroundColor))

                Divider()

                // Issues List
                if filteredIssues.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: report.isClean ? "checkmark.seal.fill" : "magnifyingglass")
                            .font(.system(size: 44))
                            .foregroundStyle(report.isClean ? .green : .secondary)

                        Text(report.isClean ? "No Diagnostics Issues Detected" : "No Matching Issues Found")
                            .font(.headline)

                        Text(report.isClean
                            ? "Your installed scenery packs, libraries, plugins, and symlinks are healthy."
                            : "Try clearing your search query or switching category filters.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 400)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(filteredIssues) { issue in
                            DiagnosticIssueRow(issue: issue) { action in
                                pluginManager.executeDiagnosticAction(action)
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                }
            } else if pluginManager.isRunningDiagnostics {
                VStack(spacing: 16) {
                    Spacer()
                    ProgressView()
                        .controlSize(.large)
                    Text("Scanning X-Plane Installation...")
                        .font(.headline)
                    Text("Analyzing apt.dat airport records, library.txt manifests, symlinks, and plugin binaries.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "cross.case.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)

                    Text("Health & Diagnostics Engine")
                        .font(.title3)
                        .fontWeight(.bold)

                    Text("Run a diagnostic scan before launching X-Plane to detect conflicting airport definitions, missing third-party libraries, broken links, and non-native plugin binaries.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)

                    Button("Run Initial Diagnostics") {
                        pluginManager.runDiagnostics()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(pluginManager.xPlanePath == nil)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            if report == nil && !pluginManager.isRunningDiagnostics && pluginManager.xPlanePath != nil {
                pluginManager.runDiagnostics()
            }
        }
    }

    // MARK: - Helper Views & Counts

    @ViewBuilder
    private func statusBanner(for report: DiagnosticsReport) -> some View {
        HStack(spacing: 14) {
            if report.criticalCount > 0 {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.title)
                    .foregroundStyle(.red)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(report.criticalCount) Critical Issue\(report.criticalCount > 1 ? "s" : "") Detected")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Text("Action is recommended to prevent simulator crashes or missing features.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if report.warningCount > 0 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(report.warningCount) Warning\(report.warningCount > 1 ? "s" : "") Found")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text("Conflicts or missing libraries may cause visual bugs or duplicate scenery.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 2) {
                    Text("All Systems Nominal")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text("No airport conflicts, missing libraries, or broken links detected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Stat capsules
            HStack(spacing: 8) {
                if !report.airportConflicts.isEmpty {
                    statPill(label: "Airport Conflicts", count: report.airportConflicts.count, color: .orange)
                }
                if !report.missingLibraries.isEmpty {
                    statPill(label: "Missing Libraries", count: report.missingLibraries.count, color: .orange)
                }
                if report.isClean {
                    statPill(label: "Healthy", count: 0, color: .green, customText: "Clean")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            (report.criticalCount > 0 ? Color.red : (report.warningCount > 0 ? Color.orange : Color.green))
                .opacity(0.08)
        )
    }

    private func statPill(label: String, count: Int, color: Color, customText: String? = nil) -> some View {
        HStack(spacing: 4) {
            Text(customText ?? "\(count)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(color.opacity(0.3), lineWidth: 1)
        )
    }

    private func issueCount(for filter: FilterCategory, in report: DiagnosticsReport) -> Int {
        switch filter {
        case .all:
            return report.issues.count
        case .conflicts:
            return report.issues.filter { $0.category == .sceneryConflict }.count
        case .libraries:
            return report.issues.filter { $0.category == .missingLibrary }.count
        case .integrity:
            return report.issues.filter { $0.category == .addonIntegrity || $0.category == .compatibility }.count
        }
    }
}

struct DiagnosticIssueRow: View {
    let issue: DiagnosticIssue
    let onQuickAction: (DiagnosticQuickAction) -> Void
    @State private var isExpanded: Bool = false

    private var severityColor: Color {
        switch issue.severity {
        case .critical: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }

    private var categoryIcon: String {
        issue.category.systemImage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: categoryIcon)
                    .font(.body)
                    .foregroundStyle(severityColor)
                    .frame(width: 24, height: 24)
                    .background(severityColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(issue.title)
                            .font(.body)
                            .fontWeight(.semibold)

                        Text(issue.severity.rawValue.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(severityColor.opacity(0.15))
                            .foregroundStyle(severityColor)
                            .clipShape(Capsule())

                        Text(issue.category.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text(issue.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if let action = issue.quickAction, let title = issue.quickActionTitle {
                    Button(title) {
                        onQuickAction(action)
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                }

                if !issue.details.isEmpty {
                    Button(action: { isExpanded.toggle() }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                }
            }

            if isExpanded && !issue.details.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                        .padding(.vertical, 2)
                    ForEach(issue.details, id: \.self) { detail in
                        Text("• \(detail)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 34)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
    }
}
