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

struct StoragePoolsSettingsSection: View {
    @Environment(PluginManager.self) private var pluginManager

    @State private var pendingPoolConfig: PendingPoolConfig?
    @State private var editingPool: StoragePool?

    @State private var poolToDelete: StoragePool?
    @State private var showDeleteConfirmation = false

    var body: some View {
        GroupBox("Storage Pools Data Folders") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Configure multiple storage root directories (internal SSD, external drives).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Add-ons are aggregated seamlessly across all registered drives. If an external drive is disconnected, its add-ons remain safely tracked.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        chooseNewPoolDirectory()
                    } label: {
                        Label("Add Storage Pool...", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                if pluginManager.storagePools.isEmpty {
                    Text("No storage pools configured. Click 'Add Storage Pool...' to configure one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 12) {
                        ForEach(pluginManager.storagePools) { pool in
                            StoragePoolCard(
                                pool: pool,
                                stats: pluginManager.storagePoolStats[pool.id],
                                isOnlyPool: pluginManager.storagePools.count <= 1,
                                onSetPrimary: {
                                    pluginManager.setPrimaryStoragePool(id: pool.id)
                                },
                                onEdit: {
                                    editingPool = pool
                                },
                                onDelete: {
                                    poolToDelete = pool
                                    showDeleteConfirmation = true
                                }
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .sheet(item: $pendingPoolConfig) { config in
            AddStoragePoolSheet(
                config: config,
                onAdd: { finalName, isPrimary, categories in
                    pluginManager.addStoragePool(
                        url: config.url,
                        name: finalName.isEmpty ? config.url.lastPathComponent : finalName,
                        isPrimary: isPrimary,
                        defaultCategories: Array(categories)
                    )
                    pendingPoolConfig = nil
                },
                onCancel: {
                    pendingPoolConfig = nil
                }
            )
        }
        .sheet(item: $editingPool) { pool in
            EditStoragePoolSheet(
                pool: pool,
                onSave: { updatedName, updatedCategories in
                    pluginManager.updateStoragePool(
                        id: pool.id,
                        name: updatedName.isEmpty ? pool.name : updatedName,
                        defaultCategories: Array(updatedCategories)
                    )
                    editingPool = nil
                },
                onCancel: {
                    editingPool = nil
                }
            )
        }
        .confirmationDialog(
            "Remove Storage Pool?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible,
            presenting: poolToDelete
        ) { pool in
            Button("Remove Pool '\(pool.name)'", role: .destructive) {
                pluginManager.removeStoragePool(id: pool.id)
                poolToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                poolToDelete = nil
            }
        } message: { pool in
            Text("This will remove the storage pool reference from XLauncher. Files on disk at '\(pool.url.path)' will not be deleted.")
        }
    }

    private func chooseNewPoolDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Storage Directory"
        panel.message = "Choose a folder on your internal drive or external SSD to store add-ons."

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.main.async {
                self.pendingPoolConfig = PendingPoolConfig(
                    url: url,
                    name: url.lastPathComponent,
                    isPrimary: self.pluginManager.storagePools.isEmpty,
                    defaultCategories: []
                )
            }
        }
    }
}

private struct PendingPoolConfig: Identifiable {
    let id = UUID()
    let url: URL
    var name: String
    var isPrimary: Bool
    var defaultCategories: Set<AddonCategory>
}

// MARK: - Storage Pool Card

private struct StoragePoolCard: View {
    let pool: StoragePool
    let stats: StoragePoolStats?
    let isOnlyPool: Bool
    let onSetPrimary: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header Row
            HStack(spacing: 8) {
                Image(systemName: pool.iconName)
                    .font(.title3)
                    .foregroundStyle(pool.isOnline ? (pool.isPrimary ? .blue : .primary) : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(pool.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        if pool.isPrimary {
                            Text("Primary")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue)
                                .clipShape(Capsule())
                        }

                        PoolStatusBadge(isOnline: pool.isOnline)
                    }

                    Text(pool.url.path)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                // Actions Menu
                Menu {
                    if !pool.isPrimary && pool.isOnline {
                        Button {
                            onSetPrimary()
                        } label: {
                            Label("Set as Primary Storage", systemImage: "star.fill")
                        }
                    }

                    Button {
                        onEdit()
                    } label: {
                        Label("Edit Configuration & Routing...", systemImage: "slider.horizontal.3")
                    }

                    Button {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: pool.url.path)
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                    .disabled(!pool.isOnline)

                    if !isOnlyPool && !pool.isPrimary {
                        Divider()
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label("Remove Storage Pool", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            // Volume Capacity Progress Bar
            if let metrics = pool.volumeMetrics, metrics.totalCapacity > 0 {
                VolumeCapacityView(metrics: metrics)
            }

            // Content Breakdown & Auto-Routing Badges
            HStack(spacing: 8) {
                if let stats = stats {
                    HStack(spacing: 6) {
                        AddonCountBadge(icon: "puzzlepiece.extension", label: "Plugins", count: stats.pluginCount, size: stats.pluginSizeBytes)
                        AddonCountBadge(icon: "map", label: "Scenery", count: stats.sceneryCount, size: stats.scenerySizeBytes)
                        AddonCountBadge(icon: "airplane", label: "Aircraft", count: stats.aircraftCount, size: stats.aircraftSizeBytes)
                        AddonCountBadge(icon: "doc.text", label: "Lua", count: stats.luaScriptCount, size: stats.luaSizeBytes)
                    }
                }

                Spacer()

                if !pool.defaultCategories.isEmpty {
                    let routesStr = "Routes: " + pool.defaultCategories.map { $0.rawValue }.joined(separator: ", ")
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.forward.and.arrow.up.backward")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(routesStr)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(pool.isPrimary ? Color.blue.opacity(0.3) : Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
        )
    }
}

private struct VolumeCapacityView: View {
    let metrics: VolumeMetrics

    private var barColor: Color {
        if metrics.usedFraction > 0.9 {
            return .red
        } else if metrics.usedFraction > 0.75 {
            return .orange
        } else {
            return .blue
        }
    }

    private var availableText: String {
        let formatted = ByteCountFormatter.string(fromByteCount: Int64(metrics.availableCapacity), countStyle: .file)
        return "\(formatted) free"
    }

    private var usageText: String {
        let used = ByteCountFormatter.string(fromByteCount: Int64(metrics.usedCapacity), countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: Int64(metrics.totalCapacity), countStyle: .file)
        return "\(used) used of \(total)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                let barWidth = max(geo.size.width * CGFloat(metrics.usedFraction), 4.0)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(NSColor.separatorColor).opacity(0.3))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(width: barWidth, height: 6)
                }
            }
            .frame(height: 6)

            HStack {
                Text(availableText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(usageText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AddonCountBadge: View {
    let icon: String
    let label: String
    let count: Int
    let size: Int64

    var body: some View {
        let sizeStr = size > 0 ? "(\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))" : ""
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.caption2)
                .fontWeight(.medium)
            if !sizeStr.isEmpty {
                Text(sizeStr)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct PoolStatusBadge: View {
    let isOnline: Bool

    var body: some View {
        if isOnline {
            HStack(spacing: 3) {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text("Online")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.green.opacity(0.12))
            .clipShape(Capsule())
        } else {
            HStack(spacing: 3) {
                Circle().fill(Color.red).frame(width: 6, height: 6)
                Text("Offline (Unmounted)")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.red.opacity(0.12))
            .clipShape(Capsule())
        }
    }
}

// MARK: - Add Storage Pool Sheet

private struct AddStoragePoolSheet: View {
    let config: PendingPoolConfig
    @State private var name: String
    @State private var isPrimary: Bool
    @State private var defaultCategories: Set<AddonCategory>

    let onAdd: (String, Bool, Set<AddonCategory>) -> Void
    let onCancel: () -> Void

    init(
        config: PendingPoolConfig,
        onAdd: @escaping (String, Bool, Set<AddonCategory>) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.config = config
        self._name = State(initialValue: config.name)
        self._isPrimary = State(initialValue: config.isPrimary)
        self._defaultCategories = State(initialValue: config.defaultCategories)
        self.onAdd = onAdd
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "plus.square.fill.on.square.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Storage Pool")
                        .font(.headline)
                    Text("Configure storage location and destination routing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Location Path")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(config.url.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Pool Display Name")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    TextField("e.g. External SSD, Fast NVMe", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                Toggle("Set as primary storage pool", isOn: $isPrimary)
                    .font(.subheadline)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Default Category Routing (Installer Targets)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Select which add-on categories should install to this drive by default:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        ForEach(AddonCategory.allCases) { category in
                            Toggle(category.rawValue, isOn: Binding(
                                get: { defaultCategories.contains(category) },
                                set: { selected in
                                    if selected {
                                        defaultCategories.insert(category)
                                    } else {
                                        defaultCategories.remove(category)
                                    }
                                }
                            ))
                            .toggleStyle(.checkbox)
                            .font(.caption)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add Pool") {
                    onAdd(name, isPrimary, defaultCategories)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}

// MARK: - Edit Storage Pool Sheet

private struct EditStoragePoolSheet: View {
    let pool: StoragePool
    @State private var name: String
    @State private var defaultCategories: Set<AddonCategory>

    let onSave: (String, Set<AddonCategory>) -> Void
    let onCancel: () -> Void

    init(
        pool: StoragePool,
        onSave: @escaping (String, Set<AddonCategory>) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.pool = pool
        self._name = State(initialValue: pool.name)
        self._defaultCategories = State(initialValue: Set(pool.defaultCategories))
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .font(.title2)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Configure Storage Pool")
                        .font(.headline)
                    Text(pool.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Path")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(pool.url.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Display Name")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    TextField("Pool name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Default Category Routing (Installer Targets)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Categories selected here will default to installing in this pool:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        ForEach(AddonCategory.allCases) { category in
                            Toggle(category.rawValue, isOn: Binding(
                                get: { defaultCategories.contains(category) },
                                set: { selected in
                                    if selected {
                                        defaultCategories.insert(category)
                                    } else {
                                        defaultCategories.remove(category)
                                    }
                                }
                            ))
                            .toggleStyle(.checkbox)
                            .font(.caption)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    onSave(name, defaultCategories)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
