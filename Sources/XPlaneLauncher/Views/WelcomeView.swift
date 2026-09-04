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

enum WelcomeStep: Int, CaseIterable {
    case features
    case setup
}

private enum NavigationDirection {
    case forward
    case backward
}

struct WelcomeView: View {
    @Environment(PluginManager.self) var pluginManager
    @Environment(UpdateManager.self) var updateManager
    @Environment(CSLManager.self) var cslManager
    @Environment(\.dismiss) private var dismiss

    var onComplete: (() -> Void)? = nil

    @State private var currentStep: WelcomeStep = .features
    @State private var navigationDirection: NavigationDirection = .forward

    var isXPlaneDetected: Bool {
        guard let path = pluginManager.xPlanePath else { return false }
        let appURL = path.appendingPathComponent("X-Plane.app")
        return FileManager.default.fileExists(atPath: appURL.path)
    }

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: navigationDirection == .forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: navigationDirection == .forward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    var body: some View {
        @Bindable var pluginManager = pluginManager

        VStack(spacing: 0) {
            ZStack {
                if currentStep == .features {
                    featuresView
                        .transition(stepTransition)
                } else {
                    setupView(pluginManager: pluginManager)
                        .transition(stepTransition)
                }
            }
            .clipped()
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Footer Action Bar
            footerView
        }
        .frame(width: 580, height: 660)
    }

    // MARK: - Step 1: Feature Overview
    private var featuresView: some View {
        ScrollView {
            VStack(spacing: 22) {
                // Hero Header
                VStack(spacing: 12) {
                    if let iconImage = NSApp.applicationIconImage {
                        Image(nsImage: iconImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                            .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                    } else {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 80, height: 80)
                            Image(systemName: "airplane.departure")
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                    }

                    VStack(spacing: 4) {
                        Text("Welcome to X-Plane Launcher")
                            .font(.system(size: 22, weight: .bold))

                        Text("Organize add-ons with symlinks, switch flight profiles seamlessly, and launch X-Plane 12 with a clean setup.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 480)
                    }
                }
                .padding(.top, 24)

                // How it Works Cards
                VStack(spacing: 10) {
                    FeatureRow(
                        icon: "folder.badge.gearshape",
                        color: .blue,
                        title: "Profiles & Storage Pools",
                        description: "Organize add-ons across multiple disks (Storage Pools) and switch profiles seamlessly. The launcher links only active add-ons into X-Plane on demand."
                    )

                    FeatureRow(
                        icon: "tag",
                        color: .indigo,
                        title: "Categorization & Custom Tagging",
                        description: "Automatically categorize aircraft, scenery, and plugins with smart heuristics. Add custom tags, override categories, and filter your library instantly."
                    )

                    FeatureRow(
                        icon: "stethoscope",
                        color: .red,
                        title: "Add-on Diagnostics & Log Analyzer",
                        description: "Detect missing scenery libraries, verify Apple Silicon (arm64) binary compatibility, diagnose crashes from Log.txt, and trace FlyWithLua/SASL errors."
                    )

                    FeatureRow(
                        icon: "internaldrive",
                        color: .mint,
                        title: "Disk Usage Analyzer & Cache Cleanup",
                        description: "Inspect storage usage across all add-ons and storage pools, identify largest space hogs and orphan add-ons, and clear shader/crash caches with one click."
                    )

                    FeatureRow(
                        icon: "square.and.arrow.down",
                        color: .purple,
                        title: "Add-on Installation & Updates",
                        description: "Drag & drop add-ons to install, manage updates with SkunkCrafts & X-Updater, and cleanly delete unwanted packages with automated symlink cleanup."
                    )

                    FeatureRow(
                        icon: "airplane",
                        color: .orange,
                        title: "CSL Models & Navigation Data",
                        description: "Manage X-CSL multiplayer models with realistic X-Plane 12 lighting, and download official AIRAC cycles directly from Navigraph."
                    )
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: - Step 2: Initial Setup
    @ViewBuilder
    private func setupView(pluginManager: PluginManager) -> some View {
        @Bindable var pm = pluginManager

        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [.blue.opacity(0.15), .indigo.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 56, height: 56)
                        Image(systemName: "gearshape.2.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.blue)
                    }

                    VStack(spacing: 4) {
                        Text("Initial Setup")
                            .font(.system(size: 20, weight: .bold))

                        Text("Configure your simulator paths and feature preferences.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 24)

                // Setup Form
                VStack(alignment: .leading, spacing: 16) {
                    // X-Plane 12 Location
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            FolderSelectorRow(
                                label: "X-Plane 12 Installation:",
                                path: pm.xPlanePath,
                                placeholder: "Select your X-Plane 12 root folder"
                            ) {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                panel.allowsMultipleSelection = false
                                panel.prompt = "Select X-Plane Folder"
                                if panel.runModal() == .OK {
                                    pm.xPlanePath = panel.url
                                }
                            }

                            if pm.xPlanePath != nil {
                                HStack(spacing: 4) {
                                    Image(systemName: isXPlaneDetected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                        .foregroundStyle(isXPlaneDetected ? .green : .yellow)
                                    Text(isXPlaneDetected ? "X-Plane 12 detected" : "X-Plane.app not found in this folder")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text("Point to the folder containing X-Plane.app (e.g., /Applications/X-Plane 12).")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                    }

                    // Central Data Folder
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            FolderSelectorRow(
                                label: "Central Data Folder:",
                                path: pm.launcherDataFolder,
                                placeholder: "Default (Application Support/XPlaneLauncher)"
                            ) {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                panel.allowsMultipleSelection = false
                                panel.prompt = "Select Central Data Folder"
                                if panel.runModal() == .OK {
                                    pm.launcherDataFolder = panel.url
                                }
                            }

                            Text("Add-ons in this folder will be organized into Plugins, Scenery, Aircraft, and LuaScripts.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                    }

                    // CSL Support
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Enable X-CSL multiplayer models support", isOn: $pm.enableCSLSupport)
                                .font(.body)

                            Text("Enables checking, installing, and updating CSL models for online networks (VATSIM, IVAO) from the X-CSL repository.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if pm.enableCSLSupport {
                                Divider()

                                Toggle("Apply modern X-Plane 12 lighting to X-CSL models", isOn: $pm.enableCSLXP12Lights)
                                    .font(.body)

                                Text("Enhances CSL aircraft with realistic parameterized lighting, dynamic strobe/beacon sequences, and ground spill effects.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }

                    // Navigation Data Support
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Enable Navigraph navdata updates", isOn: $pm.enableNavdataSupport)
                                .font(.body)

                            Text("Enables checking, installing, and updating navigation data from Navigraph for X-Plane 12 and supported add-ons.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: - Footer Bar
    private var footerView: some View {
        HStack {
            if currentStep == .features {
                if pluginManager.hasCompletedWelcome || pluginManager.isConfigured {
                    Button("Close") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }

                Spacer()

                // Step Indicator Dots
                stepDots

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        navigationDirection = .forward
                        currentStep = .setup
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Next")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(minWidth: 80)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        navigationDirection = .backward
                        currentStep = .features
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Back")
                    }
                    .frame(minWidth: 70)
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                // Step Indicator Dots
                stepDots

                Spacer()

                Button(action: {
                    pluginManager.savePath()
                    pluginManager.ensureLauncherDataDirectories()
                    pluginManager.hasCompletedWelcome = true
                    dismiss()
                    onComplete?()
                }) {
                    Text(pluginManager.hasCompletedWelcome ? "Save & Close" : "Get Started")
                        .frame(minWidth: 100)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(!isXPlaneDetected)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Step Dots Indicator
    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(WelcomeStep.allCases, id: \.self) { step in
                Circle()
                    .fill(currentStep == step ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
