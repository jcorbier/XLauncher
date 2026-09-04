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
import Charts
import AppKit

struct DiskUsageView: View {
    @Environment(PluginManager.self) var pluginManager

    @State private var selectedSubTab: SubTab = .overview
    @State private var selectedCategoryFilter: AddonStorageCategory? = nil
    @State private var searchText: String = ""
    @State private var selectedLocationFilter: String = "All"

    @State private var showingClearShaderAlert: Bool = false
    @State private var showingClearCrashAlert: Bool = false
    @State private var itemPendingDeletion: DiskUsageItem? = nil

    enum SubTab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case spaceHogs = "Space Hogs"
        case cachesAndOrphans = "Caches & Orphans"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .overview: return "chart.pie.fill"
            case .spaceHogs: return "arrow.down.right.and.arrow.up.left"
            case .cachesAndOrphans: return "trash.circle"
            }
        }
    }

    private var summary: DiskUsageSummary? {
        pluginManager.diskUsageSummary
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar

            Divider()

            if pluginManager.isScanningDiskUsage {
                scanningView
            } else if let summary = summary {
                VStack(spacing: 0) {
                    subTabBar

                    Divider()

                    switch selectedSubTab {
                    case .overview:
                        overviewView(summary: summary)
                    case .spaceHogs:
                        spaceHogsView(summary: summary)
                    case .cachesAndOrphans:
                        cachesAndOrphansView(summary: summary)
                    }
                }
            } else {
                emptyStateView
            }
        }
        .confirmationDialog(
            "Clear Shader Cache?",
            isPresented: $showingClearShaderAlert,
            titleVisibility: .visible
        ) {
            Button("Clear Shader Cache", role: .destructive) {
                Task {
                    try? await pluginManager.clearShaderCache()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("X-Plane will recompile shaders on next launch. This can free significant disk space if old or duplicate shaders have accumulated.")
        }
        .confirmationDialog(
            "Clear Crash Dumps & Diagnostic Logs?",
            isPresented: $showingClearCrashAlert,
            titleVisibility: .visible
        ) {
            Button("Clear Crash Dumps", role: .destructive) {
                Task {
                    try? await pluginManager.clearCrashReports()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Old crash logs and core dumps will be safely removed from Output/crash_reports.")
        }
        .confirmationDialog(
            "Delete Orphan Package?",
            isPresented: Binding(
                get: { itemPendingDeletion != nil },
                set: { if !$0 { itemPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let item = itemPendingDeletion {
                Button("Move to Trash", role: .destructive) {
                    Task {
                        try? await pluginManager.deleteDiskUsageItem(item)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let item = itemPendingDeletion {
                Text("Are you sure you want to delete '\(item.name)' (\(item.formattedSize))? This item is not used by any profile.")
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Add-on Disk Usage Analyzer")
                    .font(.title2)
                    .fontWeight(.bold)

                if let summary = summary {
                    Text("Total add-on storage footprint: **\(summary.formattedTotalSize)** across \(summary.totalFiles.formatted()) files.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Analyze disk space consumed by add-ons across storage pools and the primary simulator.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: {
                pluginManager.scanDiskUsage()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text(summary == nil ? "Analyze Storage" : "Rescan")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(pluginManager.isScanningDiskUsage)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Scanning & Empty States

    private var scanningView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView(value: pluginManager.diskUsageScanProgress)
                .progressViewStyle(.linear)
                .frame(maxWidth: 320)

            Text(pluginManager.diskUsageScanStatus)
                .font(.headline)
                .foregroundStyle(.primary)

            Text("Analyzing directories, skipping symlinks to avoid double-counting...")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var subTabBar: some View {
        HStack(spacing: 4) {
            ForEach(SubTab.allCases) { tab in
                let isSelected = selectedSubTab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedSubTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        ZStack {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color(NSColor.controlAccentColor))
                                    .shadow(color: Color.black.opacity(0.1), radius: 2, y: 1)
                            }
                        }
                    )
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .contentShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                )
        )
        .padding(.vertical, 8)
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("Storage Analysis Ready", systemImage: "internaldrive")
        } description: {
            Text("Click 'Analyze Storage' to measure space consumed by aircraft, scenery, plugins, and simulator caches.")
        } actions: {
            Button("Analyze Storage") {
                pluginManager.scanDiskUsage()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - SubTab 1: Overview

    private func overviewView(summary: DiskUsageSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Top Chart & Distribution Row
                HStack(alignment: .top, spacing: 24) {
                    // Swift Charts Donut Chart
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Storage by Category")
                            .font(.headline)

                        let nonZeroCategories = AddonStorageCategory.allCases.filter {
                            (summary.categorySizes[$0] ?? 0) > 0
                        }

                        if nonZeroCategories.isEmpty {
                            ContentUnavailableView("No Data", systemImage: "chart.pie")
                                .frame(height: 220)
                        } else {
                            Chart(nonZeroCategories) { cat in
                                let bytes = summary.categorySizes[cat] ?? 0
                                SectorMark(
                                    angle: .value("Bytes", bytes),
                                    innerRadius: .ratio(0.6),
                                    angularInset: 1.5
                                )
                                .foregroundStyle(cat.color)
                                .annotation(position: .overlay) {
                                    if Double(bytes) / Double(max(summary.totalBytes, 1)) > 0.15 {
                                        Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                            .frame(height: 220)
                        }
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .frame(maxWidth: .infinity)

                    // Storage Locations Breakdown
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Storage by Location")
                            .font(.headline)

                        let locations = summary.locationSizes.keys.sorted()
                        VStack(spacing: 12) {
                            ForEach(locations, id: \.self) { loc in
                                let bytes = summary.locationSizes[loc] ?? 0
                                let fraction = Double(bytes) / Double(max(summary.totalBytes, 1))

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(loc)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }

                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(Color.secondary.opacity(0.15))
                                                .frame(height: 6)

                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(Color.accentColor)
                                                .frame(width: max(geo.size.width * CGFloat(fraction), 4), height: 6)
                                        }
                                    }
                                    .frame(height: 6)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        Spacer()
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .frame(maxWidth: .infinity)
                }

                // Category Cards Grid
                Text("Category Details")
                    .font(.headline)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 14) {
                    ForEach(AddonStorageCategory.allCases) { cat in
                        let size = summary.categorySizes[cat] ?? 0
                        let fraction = Double(size) / Double(max(summary.totalBytes, 1))

                        Button {
                            selectedCategoryFilter = cat
                            selectedSubTab = .spaceHogs
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(cat.color.opacity(0.15))
                                        .frame(width: 38, height: 38)
                                    Image(systemName: cat.systemImage)
                                        .foregroundStyle(cat.color)
                                        .font(.system(size: 16, weight: .semibold))
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(cat.rawValue)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.primary)

                                    HStack(spacing: 6) {
                                        Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        Text(String(format: "(%.1f%%)", fraction * 100))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - SubTab 2: Space Hogs

    private func spaceHogsView(summary: DiskUsageSummary) -> some View {
        VStack(spacing: 0) {
            // Filter Bar
            HStack(spacing: 12) {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search add-on name...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(maxWidth: 240)

                // Category Filter
                Picker("Category", selection: $selectedCategoryFilter) {
                    Text("All Categories").tag(AddonStorageCategory?.none)
                    Divider()
                    ForEach(AddonStorageCategory.allCases) { cat in
                        Text(cat.rawValue).tag(AddonStorageCategory?.some(cat))
                    }
                }
                .frame(width: 170)

                // Location Filter
                let locations = ["All"] + Array(summary.locationSizes.keys).sorted()
                Picker("Location", selection: $selectedLocationFilter) {
                    ForEach(locations, id: \.self) { loc in
                        Text(loc).tag(loc)
                    }
                }
                .frame(width: 170)

                Spacer()

                if selectedCategoryFilter != nil || !searchText.isEmpty || selectedLocationFilter != "All" {
                    Button("Reset Filters") {
                        selectedCategoryFilter = nil
                        searchText = ""
                        selectedLocationFilter = "All"
                    }
                    .buttonStyle(.link)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Filtered Items List
            let filtered = filteredSpaceHogs(items: summary.items)
            let maxItemBytes = summary.items.first?.sizeBytes ?? 1

            if filtered.isEmpty {
                ContentUnavailableView("No Add-ons Found", systemImage: "magnifyingglass", description: Text("Try adjusting your filters or search terms."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { item in
                    HStack(spacing: 16) {
                        // Category Icon
                        ZStack {
                            Circle()
                                .fill(item.category.color.opacity(0.15))
                                .frame(width: 32, height: 32)
                            Image(systemName: item.category.systemImage)
                                .foregroundStyle(item.category.color)
                                .font(.system(size: 14))
                        }

                        // Info
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(item.name)
                                    .font(.headline)
                                    .lineLimit(1)

                                if item.isOrphan {
                                    Text("ORPHAN")
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.brown.opacity(0.2))
                                        .foregroundStyle(Color.brown)
                                        .clipShape(Capsule())
                                }
                            }

                            HStack(spacing: 8) {
                                Text(item.category.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("•")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(item.locationName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("•")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("\(item.fileCount.formatted()) files")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Spacer()

                        // Relative visual size bar
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(item.formattedSize)
                                .font(.headline)
                                .fontWeight(.semibold)

                            GeometryReader { geo in
                                ZStack(alignment: .trailing) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.secondary.opacity(0.15))
                                        .frame(height: 4)

                                    let fraction = Double(item.sizeBytes) / Double(max(maxItemBytes, 1))
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(item.category.color)
                                        .frame(width: max(geo.size.width * CGFloat(fraction), 4), height: 4)
                                }
                            }
                            .frame(width: 100, height: 4)
                        }

                        // Reveal in Finder Button
                        Button(action: {
                            NSWorkspace.shared.selectFile(item.url.path, inFileViewerRootedAtPath: item.url.deletingLastPathComponent().path)
                        }) {
                            Image(systemName: "folder")
                                .font(.subheadline)
                        }
                        .buttonStyle(.borderless)
                        .help("Reveal in Finder")
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }
        }
    }

    private func filteredSpaceHogs(items: [DiskUsageItem]) -> [DiskUsageItem] {
        var list = items

        if let cat = selectedCategoryFilter {
            list = list.filter { $0.category == cat }
        }

        if selectedLocationFilter != "All" {
            list = list.filter { $0.locationName == selectedLocationFilter }
        }

        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            let q = searchText.lowercased()
            list = list.filter {
                $0.name.lowercased().contains(q) ||
                $0.category.rawValue.lowercased().contains(q)
            }
        }

        return list
    }

    // MARK: - SubTab 3: Caches & Orphans

    private func cachesAndOrphansView(summary: DiskUsageSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Section 1: Simulator Caches & Crash Dumps
                VStack(alignment: .leading, spacing: 14) {
                    Text("Simulator Cache & Diagnostic Logs")
                        .font(.headline)

                    HStack(spacing: 16) {
                        // Shader cache card
                        let totalCacheBytes = summary.cacheItems.filter { $0.category == .caches }.reduce(0) { $0 + $1.sizeBytes }
                        cacheActionCard(
                            title: "Vulkan & Metal Shaders",
                            description: "Compiled graphics pipeline and scenery shader caches located in Output/caches.",
                            sizeBytes: totalCacheBytes,
                            icon: "cpu",
                            actionTitle: "Clear Shader Cache",
                            actionDisabled: totalCacheBytes == 0
                        ) {
                            showingClearShaderAlert = true
                        }

                        // Crash reports card
                        let totalCrashBytes = summary.cacheItems.filter { $0.category == .logsAndCrashes }.reduce(0) { $0 + $1.sizeBytes }
                        cacheActionCard(
                            title: "Crash Reports & Dump Archives",
                            description: "Accumulated crash dumps and diagnostics logs located in Output/crash_reports.",
                            sizeBytes: totalCrashBytes,
                            icon: "doc.badge.ellipsis",
                            actionTitle: "Clear Crash Dumps",
                            actionDisabled: totalCrashBytes == 0
                        ) {
                            showingClearCrashAlert = true
                        }
                    }
                }

                Divider()

                // Section 2: Orphaned Packages in Storage Pools
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Orphaned Packages in Storage Pools")
                                .font(.headline)
                            Text("Add-on packages present in your storage pools that are not referenced in any configured profile and not currently symlinked in X-Plane.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    if summary.orphanItems.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.title2)
                            Text("No orphaned packages detected across your storage pools.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        VStack(spacing: 8) {
                            ForEach(summary.orphanItems) { item in
                                HStack(spacing: 14) {
                                    Image(systemName: "questionmark.folder")
                                        .font(.title3)
                                        .foregroundStyle(.brown)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name)
                                            .font(.headline)
                                        HStack(spacing: 6) {
                                            Text(item.locationName)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text("•")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                            Text(item.formattedSize)
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                                .foregroundStyle(.primary)
                                        }
                                    }

                                    Spacer()

                                    Button("Reveal") {
                                        NSWorkspace.shared.selectFile(item.url.path, inFileViewerRootedAtPath: item.url.deletingLastPathComponent().path)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    Button(role: .destructive) {
                                        itemPendingDeletion = item
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .help("Delete Orphan Package")
                                }
                                .padding(12)
                                .background(Color(NSColor.controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func cacheActionCard(
        title: String,
        description: String,
        sizeBytes: UInt64,
        icon: String,
        actionTitle: String,
        actionDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file))
                    .font(.title3)
                    .fontWeight(.bold)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button(action: action) {
                Text(actionTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(actionDisabled)
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: .infinity)
    }
}
