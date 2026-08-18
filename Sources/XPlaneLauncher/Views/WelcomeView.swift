//
//  MIT License
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

struct WelcomeView: View {
    @Environment(PluginManager.self) var pluginManager
    @Environment(UpdateManager.self) var updateManager
    @Environment(CSLManager.self) var cslManager
    @Environment(\.dismiss) private var dismiss
    
    var onComplete: (() -> Void)? = nil
    
    var isXPlaneDetected: Bool {
        guard let path = pluginManager.xPlanePath else { return false }
        let appURL = path.appendingPathComponent("X-Plane.app")
        return FileManager.default.fileExists(atPath: appURL.path)
    }
    
    var body: some View {
        @Bindable var pluginManager = pluginManager
        
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
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
                            title: "Central Data Folder",
                            description: "Keep your add-ons organized in one place outside X-Plane. Subfolders for Plugins, Scenery, Aircraft, and LuaScripts are managed automatically."
                        )
                        
                        FeatureRow(
                            icon: "arrow.triangle.swap",
                            color: .green,
                            title: "Profiles & Symlinks",
                            description: "Create profiles for different flying scenarios (e.g. VATSIM, Offline). The launcher dynamically links only active items into your simulator."
                        )
                        
                        FeatureRow(
                            icon: "sparkles",
                            color: .orange,
                            title: "Updates & X-CSL Models",
                            description: "Stay up to date with SkunkCrafts & X-Updater, and install multiplayer CSL models with optional X-Plane 12 parameterized lighting."
                        )
                    }
                    .padding(.horizontal, 20)
                    
                    Divider()
                        .padding(.horizontal, 20)
                    
                    // Initial Setup Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Initial Setup")
                            .font(.headline)
                            .padding(.horizontal, 4)
                        
                        // X-Plane 12 Location
                        GroupBox {
                            VStack(alignment: .leading, spacing: 6) {
                                FolderSelectorRow(
                                    label: "X-Plane 12 Installation:",
                                    path: pluginManager.xPlanePath,
                                    placeholder: "Select your X-Plane 12 root folder"
                                ) {
                                    let panel = NSOpenPanel()
                                    panel.canChooseFiles = false
                                    panel.canChooseDirectories = true
                                    panel.allowsMultipleSelection = false
                                    panel.prompt = "Select X-Plane Folder"
                                    if panel.runModal() == .OK {
                                        pluginManager.xPlanePath = panel.url
                                    }
                                }
                                
                                if pluginManager.xPlanePath != nil {
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
                                    path: pluginManager.launcherDataFolder,
                                    placeholder: "Default (Application Support/XPlaneLauncher)"
                                ) {
                                    let panel = NSOpenPanel()
                                    panel.canChooseFiles = false
                                    panel.canChooseDirectories = true
                                    panel.allowsMultipleSelection = false
                                    panel.prompt = "Select Central Data Folder"
                                    if panel.runModal() == .OK {
                                        pluginManager.launcherDataFolder = panel.url
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
                                Toggle("Enable X-CSL multiplayer models support", isOn: $pluginManager.enableCSLSupport)
                                    .font(.body)
                                
                                Text("Enables checking, installing, and updating CSL models for online networks (VATSIM, IVAO) from the X-CSL repository.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                if pluginManager.enableCSLSupport {
                                    Divider()
                                    
                                    Toggle("Apply modern X-Plane 12 lighting to X-CSL models", isOn: $pluginManager.enableCSLXP12Lights)
                                        .font(.body)
                                    
                                    Text("Enhances CSL aircraft with realistic parameterized lighting, dynamic strobe/beacon sequences, and ground spill effects.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 20)
            }
            
            Divider()
            
            // Footer Action Bar
            HStack {
                if pluginManager.hasCompletedWelcome || pluginManager.isConfigured {
                    Button("Close") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                
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
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 580, height: 640)
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
