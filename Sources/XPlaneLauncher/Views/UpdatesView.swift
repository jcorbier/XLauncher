//
//  UpdatesView.swift
//  XPlaneLauncher
//

import SwiftUI

struct UpdatesView: View {
    @Environment(UpdateManager.self) var updateManager
    @State private var selectedFilter: AddonCategoryFilter = .all
    @State private var showDebugConsole: Bool = false
    
    enum AddonCategoryFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case aircraft = "Aircraft"
        case plugin = "Plugins"
        case scenery = "Scenery"
        case luaScript = "Lua Scripts"
        
        var id: String { rawValue }
    }
    
    var filteredAddons: [UpdateManager.UpdatableAddon] {
        switch selectedFilter {
        case .all:
            return updateManager.updatableAddons
        case .aircraft:
            return updateManager.updatableAddons.filter { $0.addonCategory == .aircraft }
        case .plugin:
            return updateManager.updatableAddons.filter { $0.addonCategory == .plugin }
        case .scenery:
            return updateManager.updatableAddons.filter { $0.addonCategory == .scenery }
        case .luaScript:
            return updateManager.updatableAddons.filter { $0.addonCategory == .luaScript }
        }
    }
    
    var hasAvailableUpdates: Bool {
        updateManager.updatableAddons.contains { $0.isUpdateAvailable }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                Label("Addon Updates", systemImage: "arrow.triangle.2.circlepath")
                    .font(.title3)
                    .fontWeight(.bold)
                
                Spacer()
                
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(AddonCategoryFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .frame(width: 140)
                .labelsHidden()
                
                Button(action: {
                    updateManager.scanUpdatableAddons()
                    updateManager.checkAllAddonUpdates()
                }) {
                    Label("Check for Updates", systemImage: "arrow.clockwise")
                }
                .disabled(updateManager.isProcessing)
                
                Button(action: {
                    for addon in updateManager.updatableAddons where addon.isUpdateAvailable {
                        updateManager.updateAddon(addon)
                    }
                }) {
                    Label("Update All", systemImage: "square.and.arrow.down")
                }
                .disabled(!hasAvailableUpdates || updateManager.isProcessing)
                
                Button(action: {
                    showDebugConsole.toggle()
                }) {
                    Label("Debug Console", systemImage: showDebugConsole ? "terminal.fill" : "terminal")
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // List / Empty State
            if filteredAddons.isEmpty {
                ContentUnavailableView {
                    Label("No Updatable Addons Found", systemImage: "arrow.triangle.2.circlepath")
                } description: {
                    Text("Addons with SkunkCrafts (skunkcrafts_updater.cfg) or X-Updater (x-updater.json) configuration files in your Central Data Folder will automatically appear here.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredAddons) { item in
                        UpdatableAddonRow(addon: item)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
            
            if showDebugConsole {
                Divider()
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("Live Debug Console (\(updateManager.logs.count) entries)", systemImage: "terminal")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear") {
                            updateManager.clearLogs()
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 3) {
                                ForEach(Array(updateManager.logs.enumerated()), id: \.offset) { index, log in
                                    Text(log)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(Color.green)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(index)
                                }
                            }
                            .padding(8)
                        }
                        .background(Color.black.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                        .onChange(of: updateManager.logs.count) { _, _ in
                            if let last = updateManager.logs.indices.last {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        }
                    }
                }
                .frame(height: 180)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
    }
}

struct UpdatableAddonRow: View {
    @Environment(UpdateManager.self) var updateManager
    let addon: UpdateManager.UpdatableAddon
    
    var categoryColor: Color {
        switch addon.addonCategory {
        case .aircraft: return .blue
        case .plugin: return .green
        case .scenery: return .orange
        case .luaScript: return .purple
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: addon.updaterType == .skunkcrafts ? "gearshape.2.fill" : "arrow.down.circle.fill")
                .font(.title3)
                .foregroundStyle(categoryColor)
                .frame(width: 36, height: 36)
                .background(categoryColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(addon.name)
                        .font(.body)
                        .fontWeight(.medium)
                    
                    Text(addon.addonCategory.rawValue)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(categoryColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(categoryColor.opacity(0.12))
                        .clipShape(Capsule())
                    
                    Text(addon.updaterType.rawValue)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
                
                HStack(spacing: 8) {
                    Text(addon.folderName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if let ver = addon.currentVersion {
                        Text("•  Version \(ver)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            if addon.isChecking || addon.isUpdating {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(addon.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 8) {
                    Text(addon.statusMessage)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(addon.isUpdateAvailable ? .orange : .green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(addon.isUpdateAvailable ? Color.orange.opacity(0.12) : Color.green.opacity(0.12))
                        .clipShape(Capsule())
                    
                    if addon.isUpdateAvailable {
                        let isRepair = (addon.statusMessage.lowercased().contains("repair") || (addon.currentVersion != nil && addon.latestVersion != nil && addon.currentVersion == addon.latestVersion))
                        Button(isRepair ? "Repair" : "Update") {
                            updateManager.updateAddon(addon)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(isRepair ? .orange : .accentColor)
                        .controlSize(.small)
                    } else {
                        Menu {
                            Button("Check for Updates") {
                                updateManager.checkForUpdates(for: addon)
                            }
                            Button("Verify & Repair Files") {
                                updateManager.updateAddon(addon)
                            }
                        } label: {
                            Text("Check")
                        } primaryAction: {
                            updateManager.checkForUpdates(for: addon)
                        }
                        .menuStyle(.borderedButton)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
        .contextMenu {
            Button("Check for Updates") {
                updateManager.checkForUpdates(for: addon)
            }
            Button("Verify & Repair Files") {
                updateManager.updateAddon(addon)
            }
            Divider()
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([addon.folderURL])
            }
        }
    }
}
