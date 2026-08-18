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

struct CSLListView: View {
    @Environment(PluginManager.self) var pluginManager
    @Environment(CSLManager.self) var cslManager
    
    @State private var selectedFilter: CSLFilter = .all
    @State private var searchText: String = ""
    @State private var showDebugConsole: Bool = false
    
    enum CSLFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case installed = "Installed"
        case updates = "Updates"
        case notInstalled = "Available"
        
        var id: String { rawValue }
    }
    
    var filteredPackages: [CSLPackage] {
        var result = cslManager.packages
        
        switch selectedFilter {
        case .all:
            break
        case .installed:
            result = result.filter { $0.isInstalled }
        case .updates:
            result = result.filter { $0.isInstalled && $0.status == .needsUpdate }
        case .notInstalled:
            result = result.filter { !$0.isInstalled }
        }
        
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(query) ||
                $0.title.lowercased().contains(query)
            }
        }
        
        return result
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                Label("CSL Models", systemImage: "airplane.circle")
                    .font(.title3)
                    .fontWeight(.bold)
                
                if !cslManager.packages.isEmpty {
                    Text("\(cslManager.installedCount) Installed • \(cslManager.updatesAvailableCount) Updates")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
                
                Spacer()
                
                // Search Field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search CSL models...", text: $searchText)
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
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(width: 180)
                
                // Filter Picker
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(CSLFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .frame(width: 120)
                .labelsHidden()
                
                // Check for Updates Button
                Button(action: {
                    cslManager.scanAndCheck()
                }) {
                    HStack(spacing: 4) {
                        if cslManager.isChecking {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Check")
                    }
                }
                .disabled(cslManager.isProcessing)
                
                // Update All Button
                Button(action: {
                    cslManager.updateAll()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Update All")
                        if cslManager.updatesAvailableCount > 0 {
                            Text("(\(cslManager.updatesAvailableCount))")
                                .fontWeight(.bold)
                        }
                    }
                }
                .disabled(cslManager.updatesAvailableCount == 0 || cslManager.isProcessing)
                
                // Open CSL Folder
                if let folder = pluginManager.cslPath {
                    Button(action: {
                        if !FileManager.default.fileExists(atPath: folder.path) {
                            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        }
                        NSWorkspace.shared.activateFileViewerSelecting([folder])
                    }) {
                        Image(systemName: "folder")
                    }
                    .help("Open CSL folder in Finder")
                }
                
                // Debug Console Button
                Button(action: {
                    showDebugConsole.toggle()
                }) {
                    Label("Console", systemImage: showDebugConsole ? "terminal.fill" : "terminal")
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Content
            if cslManager.isChecking && cslManager.packages.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading X-CSL package index from server...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredPackages.isEmpty {
                ContentUnavailableView {
                    Label("No CSL Models Found", systemImage: "airplane.circle")
                } description: {
                    if !searchText.isEmpty {
                        Text("No CSL models match '\(searchText)'.")
                    } else if selectedFilter == .installed {
                        Text("No CSL models are currently installed in Resources/plugins/IVAO_CSL/CSL.")
                    } else if selectedFilter == .updates {
                        Text("All installed CSL models are up to date.")
                    } else {
                        Text("Click 'Check' above to fetch the latest index of X-CSL packages.")
                    }
                } actions: {
                    if !searchText.isEmpty {
                        Button("Clear Search") { searchText = "" }
                    } else {
                        Button("Check for CSL Models") { cslManager.scanAndCheck() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredPackages) { package in
                        CSLPackageRow(package: package)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
            
            // Console Drawer
            if showDebugConsole {
                Divider()
                ConsoleView(title: "CSL Console", logger: cslManager.logger)
            }
        }
        .onAppear {
            if cslManager.cslFolderURL == nil {
                cslManager.cslFolderURL = pluginManager.cslPath
            }
            if cslManager.packages.isEmpty {
                cslManager.scanAndCheck()
            }
        }
    }
}

// MARK: - CSL Package Row

struct CSLPackageRow: View {
    @Environment(PluginManager.self) var pluginManager
    @Environment(CSLManager.self) var cslManager
    let package: CSLPackage
    
    var statusColor: Color {
        switch package.status {
        case .upToDate: return .green
        case .needsUpdate: return .orange
        case .notInstalled: return .secondary
        case .checking, .updating: return .blue
        case .error: return .red
        }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: "airplane")
                    .font(.title3)
                    .foregroundStyle(package.isInstalled ? Color.accentColor : Color.secondary)
                    .frame(width: 36, height: 36)
                    .background((package.isInstalled ? Color.accentColor : Color.secondary).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                // Package Info
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(package.name)
                            .font(.body)
                            .fontWeight(.bold)
                        
                        if package.title != package.name && !package.title.isEmpty {
                            Text(package.title)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        
                        if package.isInstalled {
                            Text("Installed")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    
                    HStack(spacing: 8) {
                        Text("\(package.fileCount) files")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("•  \(package.formattedTotalSize)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        if !package.lastUpdated.isEmpty {
                            Text("•  Updated \(package.lastUpdated)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Status & Actions
                if package.status == .updating {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        
                        Button("Cancel") {
                            cslManager.cancelUpdate(package)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                } else if package.status == .checking {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Verifying...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 8) {
                        // Status Badge
                        if package.status == .needsUpdate {
                            Text("Update: \(package.filesToUpdate) files (\(package.formattedUpdateSize))")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.12))
                                .clipShape(Capsule())
                        } else if package.status == .upToDate {
                            Text("Up to date")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.12))
                                .clipShape(Capsule())
                        } else if package.status == .error {
                            Text("Error")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.red)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.red.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        
                        // Action Buttons
                        if package.status == .needsUpdate {
                            Button("Update") {
                                cslManager.updatePackage(package)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .controlSize(.small)
                        } else if !package.isInstalled {
                            Button("Install") {
                                cslManager.updatePackage(package)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        } else {
                            Menu {
                                Button("Verify Files") {
                                    cslManager.verifyPackage(package)
                                }
                                Button("Reinstall Package") {
                                    cslManager.updatePackage(package)
                                }
                                if let cslFolder = pluginManager.cslPath {
                                    let pkgDir = cslFolder.appendingPathComponent(package.name)
                                    Button("Show in Finder") {
                                        NSWorkspace.shared.activateFileViewerSelecting([pkgDir])
                                    }
                                }
                            } label: {
                                Text("Actions")
                            } primaryAction: {
                                cslManager.verifyPackage(package)
                            }
                            .menuStyle(.borderedButton)
                            .controlSize(.small)
                        }
                    }
                }
            }
            
            // Progress Bar (when downloading)
            if package.status == .updating {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: package.downloadProgress)
                        .progressViewStyle(.linear)
                    
                    HStack {
                        Text(package.statusMessage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        Spacer()
                        
                        Text("\(Int(package.downloadProgress * 100))%")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 2)
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
            if package.status == .needsUpdate {
                Button("Update") {
                    cslManager.updatePackage(package)
                }
            } else if !package.isInstalled {
                Button("Install") {
                    cslManager.updatePackage(package)
                }
            } else {
                Button("Verify Files") {
                    cslManager.verifyPackage(package)
                }
                Button("Reinstall") {
                    cslManager.updatePackage(package)
                }
            }
            
            Divider()
            
            if package.isInstalled, let cslFolder = pluginManager.cslPath {
                let pkgDir = cslFolder.appendingPathComponent(package.name)
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([pkgDir])
                }
            }
            
            Button("Copy Package Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(package.name, forType: .string)
            }
        }
    }
}
