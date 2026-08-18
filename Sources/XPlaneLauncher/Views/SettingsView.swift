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

struct SettingsView: View {
    @Environment(PluginManager.self) var pluginManager
    @Environment(AppUpdateManager.self) var appUpdateManager
    @Environment(CSLManager.self) var cslManager
    @Environment(UpdateManager.self) var updateManager
    @State private var selectedEnvVarId: PluginManager.ScriptEnvVar.ID?
    @State private var showWelcomeSheet: Bool = false
    @State private var showReleaseNotesSheet: Bool = false
    
    private var lastCheckedFormatted: String {
        guard let date = appUpdateManager.lastCheckDate else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    var body: some View {
        @Bindable var pluginManager = pluginManager
        @Bindable var appUpdateManager = appUpdateManager
        @Bindable var cslManager = cslManager
        @Bindable var updateManager = updateManager
        
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                Label("Settings", systemImage: "gearshape")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(spacing: 20) {
                    GroupBox("General") {
                        VStack(spacing: 8) {
                            FolderSelectorRow(label: "X-Plane Location:", path: pluginManager.xPlanePath, placeholder: "Select X-Plane 12 folder") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                panel.allowsMultipleSelection = false
                                panel.prompt = "Select X-Plane Folder"
                                if panel.runModal() == .OK {
                                    pluginManager.xPlanePath = panel.url
                                }
                            }
                            
                            Divider()

                            FolderSelectorRow(label: "Central Data Folder:", path: pluginManager.launcherDataFolder, placeholder: "Default (Application Support/XPlaneLauncher)") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                panel.allowsMultipleSelection = false
                                panel.prompt = "Select Central Data Folder"
                                if panel.runModal() == .OK {
                                    pluginManager.launcherDataFolder = panel.url
                                }
                            }
                            
                            Divider()
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Welcome Guide")
                                        .font(.subheadline)
                                    Text("Review the setup assistant and feature overview.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Button("Show Welcome Screen...") {
                                    showWelcomeSheet = true
                                }
                            }
                        }
                        .padding(8)
                    }
                    
                    GroupBox("Automatic Updates") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Configure which components automatically check for new versions on startup.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle("X-Plane Launcher application", isOn: $appUpdateManager.automaticallyCheckOnLaunch)
                                    .font(.body)
                                
                                Toggle("SkunkCrafts add-ons", isOn: $updateManager.automaticallyCheckSkunkCraftsUpdates)
                                    .font(.body)
                                
                                Toggle("X-Updater add-ons", isOn: $updateManager.automaticallyCheckXUpdaterUpdates)
                                    .font(.body)
                                
                                Toggle("X-CSL models", isOn: $cslManager.automaticallyCheckCSLUpdates)
                                    .font(.body)
                                    .disabled(!pluginManager.enableCSLSupport)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                    
                    GroupBox("Application Updates") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Include pre-release and beta versions", isOn: $appUpdateManager.includePrereleases)
                                .font(.body)
                                .onChange(of: appUpdateManager.includePrereleases) { _, _ in
                                    appUpdateManager.checkForUpdates(manual: false)
                                }
                            
                            Divider()
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        if appUpdateManager.isChecking {
                                            ProgressView()
                                                .controlSize(.small)
                                            Text("Checking GitHub for updates...")
                                                .font(.subheadline)
                                        } else if appUpdateManager.isUpdateAvailable {
                                            Image(systemName: "sparkles")
                                                .foregroundStyle(.orange)
                                            Text(appUpdateManager.statusMessage)
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                        } else {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                            Text(appUpdateManager.statusMessage)
                                                .font(.subheadline)
                                        }
                                    }
                                    
                                    if appUpdateManager.lastCheckDate != nil {
                                        Text("Last checked: \(lastCheckedFormatted)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    appUpdateManager.checkForUpdates(manual: true)
                                }) {
                                    Label("Check Now", systemImage: "arrow.clockwise")
                                }
                                .disabled(appUpdateManager.isChecking)
                            }
                            
                            if appUpdateManager.isUpdateAvailable, let release = appUpdateManager.latestRelease {
                                Divider()
                                
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("New Version Available: \(release.displayTitle)")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Text("Released on GitHub. You can download the latest installer (.dmg) or view the changelog.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Button("What's New") {
                                        showReleaseNotesSheet = true
                                    }
                                    .controlSize(.small)
                                    
                                    Button(action: {
                                        appUpdateManager.downloadLatestDMG()
                                    }) {
                                        Label(
                                            release.dmgAsset != nil ? "Download DMG (\(release.dmgAsset!.formattedSize))" : "Download Update",
                                            systemImage: "arrow.down.circle.fill"
                                        )
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                                .padding(8)
                                .background(Color.orange.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                    
                    GroupBox("X-CSL Models") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Enable X-CSL support", isOn: $pluginManager.enableCSLSupport)
                                .font(.body)
                            
                            Text("When enabled, adds a CSL tab in the sidebar to check, install, and update CSL models in Resources/plugins/IVAO_CSL/CSL from the X-CSL repository.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            if pluginManager.enableCSLSupport {
                                Divider()
                                
                                Toggle("Apply modern X-Plane 12 lighting to X-CSL models", isOn: $pluginManager.enableCSLXP12Lights)
                                    .font(.body)
                                    .disabled(cslManager.isApplyingLights == true)
                                
                                Text("Upgrades X-CSL aircraft lights to native X-Plane 12 parameterized lighting with realistic billboard and ground spill effects, gear retraction animations, and dynamic strobe/beacon sequences. Original files are backed up (.bak) and models remain synchronized with server updates.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                if cslManager.isApplyingLights == true {
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text("Updating CSL model lighting...")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.top, 2)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                    
                    GroupBox("Script Environment") {
                        VStack(spacing: 0) {
                            Table($pluginManager.scriptEnvironment, selection: $selectedEnvVarId) {
                                TableColumn("Environment Variable") { $envVar in
                                    TextField("Key", text: $envVar.key)
                                        .labelsHidden()
                                        .textFieldStyle(.plain)
                                }
                                TableColumn("Value") { $envVar in
                                    TextField("Value", text: $envVar.value)
                                        .labelsHidden()
                                        .textFieldStyle(.plain)
                                }
                            }
                            .frame(minHeight: 160)
                            .scrollContentBackground(.hidden)
                            .background(Color(NSColor.controlBackgroundColor))
                            .border(Color(NSColor.separatorColor), width: 1)
                            
                            HStack {
                                Button(action: {
                                    pluginManager.scriptEnvironment.append(PluginManager.ScriptEnvVar(key: "NEW_VAR", value: "VALUE"))
                                }) {
                                    Image(systemName: "plus")
                                        .frame(width: 20, height: 20)
                                }
                                
                                Button(action: {
                                    if let selectedId = selectedEnvVarId {
                                        pluginManager.scriptEnvironment.removeAll { $0.id == selectedId }
                                        selectedEnvVarId = nil
                                    }
                                }) {
                                    Image(systemName: "minus")
                                        .frame(width: 20, height: 20)
                                }
                                .disabled(selectedEnvVarId == nil)
                                
                                Spacer()
                            }
                            .padding(.top, 8)
                        }
                        .padding(8)
                    }
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showWelcomeSheet) {
            WelcomeView()
        }
        .sheet(isPresented: $showReleaseNotesSheet) {
            let releases = appUpdateManager.newReleases.isEmpty ? (appUpdateManager.latestRelease.map { [$0] } ?? []) : appUpdateManager.newReleases
            AppReleaseNotesSheet(releases: releases)
        }
    }
}
