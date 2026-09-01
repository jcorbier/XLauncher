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

struct AddonInstallerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PluginManager.self) private var pluginManager

    let analysis: AddonPackageAnalysis

    @State private var selectedCategory: AddonCategory
    @State private var packageName: String
    @State private var selectedStoragePoolId: UUID?
    @State private var enableImmediately: Bool = true
    @State private var isInstalling: Bool = false
    @State private var progressFraction: Double = 0.0
    @State private var progressMessage: String = ""
    @State private var errorMessage: String? = nil

    init(analysis: AddonPackageAnalysis) {
        self.analysis = analysis
        _selectedCategory = State(initialValue: analysis.detectedCategory)
        _packageName = State(initialValue: analysis.suggestedPackageName)
    }

    private var activeStoragePool: StoragePool? {
        if let id = selectedStoragePoolId,
           let pool = pluginManager.storagePools.first(where: { $0.id == id && $0.isOnline }) {
            return pool
        }
        return StoragePoolService.shared.resolveDestinationPool(category: selectedCategory, in: pluginManager.storagePools)
            ?? pluginManager.primaryStoragePool
    }

    private var destinationPreviewPath: String {
        guard let pool = activeStoragePool else { return "No online storage pool configured" }
        return PathService.shared.dataFolder(selectedCategory.subfolder, in: pool.url)
            .appendingPathComponent(packageName.isEmpty ? "..." : packageName)
            .path
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Install Add-on Package")
                        .font(.headline)
                    Text(analysis.sourceURL.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .truncationMode(.middle)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Main Configuration Form
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Package Details Box
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: selectedCategory.icon)
                                .foregroundStyle(.blue)
                            Text("Package Information")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: Int64(analysis.totalUncompressedSize), countStyle: .file))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if !analysis.detectedIndicators.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(analysis.detectedIndicators, id: \.self) { indicator in
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.green)
                                        Text(indicator)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Form Fields
                    VStack(alignment: .leading, spacing: 14) {
                        // Category Picker
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Add-on Category")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Picker("", selection: $selectedCategory) {
                                ForEach(AddonCategory.allCases) { category in
                                    Label(category.rawValue, systemImage: category.icon).tag(category)
                                }
                            }
                            .pickerStyle(.segmented)
                            .disabled(isInstalling)
                            .onChange(of: selectedCategory) { _, newCategory in
                                if let routed = StoragePoolService.shared.resolveDestinationPool(category: newCategory, in: pluginManager.storagePools) {
                                    selectedStoragePoolId = routed.id
                                }
                            }
                        }

                        // Storage Location Picker
                        if pluginManager.storagePools.count > 1 {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Destination Storage Pool")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Spacer()
                                    if let pool = activeStoragePool, let metrics = pool.volumeMetrics {
                                        Text("\(ByteCountFormatter.string(fromByteCount: Int64(metrics.availableCapacity), countStyle: .file)) free")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Picker("", selection: Binding(
                                    get: { activeStoragePool?.id ?? pluginManager.storagePools.first?.id ?? UUID() },
                                    set: { selectedStoragePoolId = $0 }
                                )) {
                                    ForEach(pluginManager.storagePools) { pool in
                                        HStack {
                                            Text(pool.name)
                                            if pool.isPrimary {
                                                Text("(Primary)")
                                                    .foregroundStyle(.secondary)
                                            }
                                            if !pool.isOnline {
                                                Text("(Offline)")
                                                    .foregroundStyle(.red)
                                            }
                                        }
                                        .tag(pool.id)
                                    }
                                }
                                .disabled(isInstalling)
                            }
                        }

                        // Package Name TextField
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Folder / Package Name")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            TextField("Enter package name", text: $packageName)
                                .textFieldStyle(.roundedBorder)
                                .disabled(isInstalling)
                        }

                        // Destination Path Preview
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Install Destination")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if let pool = activeStoragePool {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(pool.isOnline ? Color.green : Color.red)
                                            .frame(width: 6, height: 6)
                                        Text(pool.name)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            Text(destinationPreviewPath)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(NSColor.controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }

                        // Options
                        Toggle("Enable immediately after installation", isOn: $enableImmediately)
                            .font(.subheadline)
                            .disabled(isInstalling)
                    }

                    // Progress Section (when active)
                    if isInstalling {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: progressFraction, total: 1.0)
                            Text(progressMessage)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(.top, 6)
                    }

                    // Error Message Banner
                    if let error = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                            Spacer()
                        }
                        .padding(10)
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(20)
            }
            .onAppear {
                if let routed = StoragePoolService.shared.resolveDestinationPool(category: selectedCategory, in: pluginManager.storagePools) {
                    selectedStoragePoolId = routed.id
                }
            }

            Divider()

            // Footer Actions
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isInstalling)

                Spacer()

                Button("Install Add-on") {
                    startInstallation()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isInstalling || packageName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || activeStoragePool == nil || activeStoragePool?.isOnline == false)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 520, idealWidth: 560, maxWidth: 640, minHeight: 480, idealHeight: 540, maxHeight: 620)
    }

    private func startInstallation() {
        guard let targetPool = activeStoragePool, targetPool.isOnline else {
            errorMessage = "Selected storage pool is offline or not configured."
            return
        }

        let targetCategory = selectedCategory
        let name = packageName.trimmingCharacters(in: .whitespacesAndNewlines)

        isInstalling = true
        errorMessage = nil
        progressFraction = 0.0
        progressMessage = "Starting installation..."

        Task {
            do {
                let installedURL = try await AddonInstallerService.shared.install(
                    analysis: analysis,
                    category: targetCategory,
                    packageName: name,
                    storagePool: targetPool,
                    progressHandler: { fraction, msg in
                        Task { @MainActor in
                            self.progressFraction = fraction
                            self.progressMessage = msg
                        }
                    }
                )

                await MainActor.run {
                    ConsoleLogger.shared.log("Installed \(targetCategory.rawValue) '\(name)' to \(installedURL.path) (\(targetPool.name))", category: targetCategory.logCategory)

                    // Rescan and optionally enable
                    switch targetCategory {
                    case .plugins:
                        pluginManager.scanPlugins()
                        if enableImmediately, let item = pluginManager.plugins.first(where: { $0.folderName == name }), !item.isEnabled {
                            pluginManager.togglePlugin(item)
                        }
                    case .scenery:
                        pluginManager.scanScenery()
                        if !enableImmediately, let item = pluginManager.scenery.first(where: { $0.folderName == name }), item.isEnabled {
                            pluginManager.toggleScenery(item)
                        } else if enableImmediately {
                            pluginManager.saveSceneryOrder()
                        }
                    case .aircraft:
                        pluginManager.scanAircraft()
                        if enableImmediately, let item = pluginManager.aircraft.first(where: { $0.folderName == name }), !item.isEnabled {
                            pluginManager.toggleAircraft(item)
                        }
                    case .luaScripts:
                        pluginManager.scanLuaScripts()
                        if enableImmediately, let item = pluginManager.luaScripts.first(where: { $0.folderName == name || $0.name == name }), !item.isEnabled {
                            pluginManager.toggleLuaScript(item)
                        }
                    }

                    pluginManager.refreshStoragePoolStats()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.isInstalling = false
                    self.errorMessage = error.localizedDescription
                    ConsoleLogger.shared.log("Failed to install \(targetCategory.rawValue) '\(name)': \(error.localizedDescription)", category: targetCategory.logCategory, level: .error)
                }
            }
        }
    }
}
