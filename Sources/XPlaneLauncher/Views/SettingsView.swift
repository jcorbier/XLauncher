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
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(PluginManager.self) var pluginManager
    @Environment(AppUpdateManager.self) var appUpdateManager
    @Environment(CSLManager.self) var cslManager
    @Environment(UpdateManager.self) var updateManager
    @Environment(NavdataManager.self) var navdataManager
    @Environment(SimSessionManager.self) var simSessionManager
    @Environment(LicenseManager.self) var licenseManager
    @Environment(AppPluginRegistry.self) var appPluginRegistry: AppPluginRegistry?
    @State private var selectedEnvVarId: PluginManager.ScriptEnvVar.ID?
    @State private var showWelcomeSheet: Bool = false
    @State private var showReleaseNotesSheet: Bool = false
    @State private var showAdvancedSettings: Bool = false
    @State private var launchArgumentsText: String = ""
    @FocusState private var isArgumentsFieldFocused: Bool
    @State private var activeProSheet: ProSheetView? = nil
    @State private var showDeactivateAlert: Bool = false
    @State private var copiedLicenseKey: Bool = false

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
        @Bindable var navdataManager = navdataManager
        @Bindable var simSessionManager = simSessionManager

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
                VStack(spacing: 16) {
                    GroupBox("X-Plane Installation") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Select your X-Plane 12 root folder to enable simulator launching, add-on symlinking, and scenery management.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("X-Plane Location")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text(pluginManager.xPlanePath?.path ?? "Not configured")
                                        .font(.caption)
                                        .fontDesign(.monospaced)
                                        .foregroundStyle(pluginManager.xPlanePath != nil ? .primary : .secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }

                                Spacer()

                                Button("Browse...") {
                                    let panel = NSOpenPanel()
                                    panel.canChooseFiles = false
                                    panel.canChooseDirectories = true
                                    panel.allowsMultipleSelection = false
                                    panel.prompt = "Select X-Plane Folder"
                                    if panel.runModal() == .OK {
                                        pluginManager.xPlanePath = panel.url
                                    }
                                }
                            }

                            if let path = pluginManager.xPlanePath {
                                let isXPlaneDetected = FileManager.default.fileExists(atPath: path.appendingPathComponent("X-Plane.app").path) || FileManager.default.fileExists(atPath: path.appendingPathComponent("X-Plane-x86_64").path)
                                HStack(spacing: 4) {
                                    Image(systemName: isXPlaneDetected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                        .foregroundStyle(isXPlaneDetected ? .green : .yellow)
                                    Text(isXPlaneDetected ? "X-Plane 12 installation detected" : "X-Plane executable not found in this folder")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                HStack(spacing: 8) {
                                    ProBadgeView(size: 12)
                                    Text("XLauncher Pro Edition")
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                }

                                Spacer()

                                if licenseManager.isPro {
                                    HStack(spacing: 5) {
                                        Image(systemName: "checkmark.seal.fill")
                                            .foregroundStyle(.green)
                                        Text("Active")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.green)
                                    }
                                } else {
                                    Text("Standard Edition")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if licenseManager.isPro, let license = licenseManager.licenseRecord {
                                Divider()

                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 6) {
                                            Text("License Key:")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(license.maskedKey)
                                                .font(.caption)
                                                .fontDesign(.monospaced)
                                                .fontWeight(.semibold)
                                        }

                                        HStack(spacing: 6) {
                                            Text("Activated Machine:")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(license.machineName)
                                                .font(.caption)
                                                .fontWeight(.medium)
                                        }

                                        HStack(spacing: 6) {
                                            Text("License Type:")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text("Node-locked lifetime license (up to 3 Macs)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()
                                }

                                HStack(spacing: 8) {
                                    Button {
                                        exportLicenseFile(licenseKey: license.licenseKey)
                                    } label: {
                                        Label("Export License File...", systemImage: "square.and.arrow.down")
                                    }
                                    .controlSize(.small)

                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(license.licenseKey, forType: .string)
                                        copiedLicenseKey = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                            copiedLicenseKey = false
                                        }
                                    } label: {
                                        Label(copiedLicenseKey ? "Copied!" : "Copy Key", systemImage: copiedLicenseKey ? "checkmark" : "doc.on.doc")
                                    }
                                    .controlSize(.small)

                                    Spacer()

                                    Button(role: .destructive) {
                                        showDeactivateAlert = true
                                    } label: {
                                        Text("Deactivate Machine...")
                                    }
                                    .controlSize(.small)
                                }
                            } else {
                                Text("Unlock streaming satellite orthophoto scenery, multi-machine support (up to 3 Macs), and priority updates.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 8) {
                                    Button("Upgrade to Pro...") {
                                        activeProSheet = .purchase
                                    }
                                    .controlSize(.small)
                                    .buttonStyle(.borderedProminent)

                                    Button("Open License File...") {
                                        activeProSheet = .activateLicense
                                    }
                                    .controlSize(.small)

                                    if let info = licenseManager.productInfo {
                                        Text("Lifetime license • \(info.formattedPrice)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    } label: {
                        Text("Licensing & Edition")
                    }

                    StoragePoolsSettingsSection()

                    GroupBox("General & Assistance") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Welcome Guide")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }

                    GroupBox("Simulator Launch & Companion Mode") {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("When X-Plane launches:")
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                Picker("", selection: $simSessionManager.launchBehavior) {
                                    ForEach(LaunchBehavior.allCases) { behavior in
                                        Text(behavior.displayName).tag(behavior)
                                    }
                                }
                                .pickerStyle(.radioGroup)

                                Text(simSessionManager.launchBehavior.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if simSessionManager.launchBehavior == .minimizeToMenuBar {
                                Divider()

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("When X-Plane exits:")
                                        .font(.subheadline)
                                        .fontWeight(.medium)

                                    Picker("", selection: $simSessionManager.simExitBehavior) {
                                        ForEach(SimExitBehavior.allCases) { behavior in
                                            Text(behavior.displayName).tag(behavior)
                                        }
                                    }
                                    .pickerStyle(.radioGroup)

                                    Text(simSessionManager.simExitBehavior.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
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

                                Toggle("Navigation data (Navigraph)", isOn: $navdataManager.automaticallyCheckNavdataUpdates)
                                    .font(.body)
                                    .disabled(!pluginManager.enableNavdataSupport)
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
                                        Text("Released on GitHub. You can update now or view the changelog.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    if appUpdateManager.isSparkleUpdating {
                                        HStack(spacing: 8) {
                                            ProgressView()
                                                .controlSize(.small)
                                            Text(appUpdateManager.sparkleStatus.isEmpty ? "Updating..." : appUpdateManager.sparkleStatus)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    } else {
                                        Button("What's New") {
                                            showReleaseNotesSheet = true
                                        }
                                        .controlSize(.small)

                                        Button(action: {
                                            appUpdateManager.startInAppUpdate()
                                        }) {
                                            Label("Update & Relaunch", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                    }
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

                    GroupBox("Navigation Data") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Enable Navigraph navdata updates", isOn: $pluginManager.enableNavdataSupport)
                                .font(.body)

                            Text("When enabled, adds a Navigation Data tab in the sidebar to download and update AIRAC cycles directly from Navigraph for X-Plane and supported add-ons.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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

                    DisclosureGroup("Advanced Settings", isExpanded: $showAdvancedSettings) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Custom command-line arguments passed to X-Plane whenever the simulator is launched.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                Image(systemName: "terminal")
                                    .foregroundStyle(.secondary)

                                TextField("Arguments (e.g. --force_windowed --no_sound)", text: $launchArgumentsText)
                                    .textFieldStyle(.roundedBorder)
                                    .fontDesign(.monospaced)
                                    .focused($isArgumentsFieldFocused)
                                    .onSubmit {
                                        pluginManager.launchArguments = launchArgumentsText
                                    }
                                    .onChange(of: isArgumentsFieldFocused) { _, focused in
                                        if !focused {
                                            pluginManager.launchArguments = launchArgumentsText
                                        }
                                    }

                                if !launchArgumentsText.isEmpty {
                                    Button(action: {
                                        launchArgumentsText = ""
                                        pluginManager.launchArguments = ""
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.top, 6)
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    if let appPluginRegistry, !appPluginRegistry.settingsPanes.isEmpty {
                        ForEach(appPluginRegistry.settingsPanes) { pane in
                            GroupBox(pane.title) {
                                pane.viewBuilder()
                                    .padding(8)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            launchArgumentsText = pluginManager.launchArguments
        }
        .onDisappear {
            pluginManager.launchArguments = launchArgumentsText
        }
        .sheet(isPresented: $showWelcomeSheet) {
            WelcomeView()
        }
        .sheet(isPresented: $showReleaseNotesSheet) {
            let releases = appUpdateManager.newReleases.isEmpty ? (appUpdateManager.latestRelease.map { [$0] } ?? []) : appUpdateManager.newReleases
            AppReleaseNotesSheet(releases: releases)
        }
        .sheet(item: $activeProSheet) { sheetView in
            ProActivationSheet(initialView: sheetView)
        }
        .alert("Deactivate XLauncher Pro?", isPresented: $showDeactivateAlert) {
            Button("Deactivate", role: .destructive) {
                Task {
                    try? await licenseManager.deactivateLicense()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deactivating this machine will release its seat on Keygen and revert this Mac to the standard edition. You can reactivate anytime with your license key.")
        }
    }

    private func exportLicenseFile(licenseKey: String) {
        let savePanel = NSSavePanel()
        savePanel.title = "Save XLauncher Pro License File"
        savePanel.nameFieldStringValue = "xlauncher.lic"
        savePanel.prompt = "Save License"
        savePanel.allowedContentTypes = [
            .plainText,
            .item,
            UTType(filenameExtension: "lic") ?? .item
        ]

        if savePanel.runModal() == .OK, let url = savePanel.url {
            try? licenseKey.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
