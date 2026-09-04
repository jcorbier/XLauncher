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

struct ProfileSelectorView: View {
    @Environment(PluginManager.self) var pluginManager
    @Environment(\.openWindow) private var openWindow
    @State private var showingSaveProfileAlert = false
    @State private var isHovered = false
    @State private var newProfileName = ""

    private var currentProfile: PluginProfile? {
        pluginManager.selectedProfile
    }

    private var hasMissingAddons: Bool {
        guard let profile = currentProfile else { return false }
        return pluginManager.hasMissingAddons(for: profile)
    }

    private var totalActiveAddons: Int {
        guard let profile = currentProfile else {
            return pluginManager.aircraft.filter { $0.isEnabled }.count +
                   pluginManager.plugins.filter { $0.isEnabled }.count +
                   pluginManager.scenery.filter { $0.isEnabled }.count +
                   pluginManager.luaScripts.filter { $0.isEnabled }.count
        }
        return profile.aircraftFolderNames.count +
               profile.pluginFolderNames.count +
               profile.sceneryFolderNames.count +
               profile.luaScriptFolderNames.count
    }

    var body: some View {
        @Bindable var pluginManager = pluginManager

        HStack(spacing: 12) {
            // Profile Selector Button & Menu
            HStack(spacing: 8) {
                Text("Profile:")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                Menu {
                    Section("Active Profile") {
                        Button {
                            pluginManager.selectedProfileId = nil
                        } label: {
                            HStack {
                                Text("None / Custom")
                                if pluginManager.selectedProfileId == nil {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }

                        ForEach(pluginManager.profiles) { profile in
                            Button {
                                pluginManager.selectedProfileId = profile.id
                            } label: {
                                HStack {
                                    Text(profile.name)
                                    if pluginManager.selectedProfileId == profile.id {
                                        Image(systemName: "checkmark")
                                    }
                                    if pluginManager.hasMissingAddons(for: profile) {
                                        Text("⚠️")
                                    }
                                }
                            }
                        }
                    }

                    Divider()

                    Button {
                        newProfileName = ""
                        showingSaveProfileAlert = true
                    } label: {
                        Label("Save Current Setup as New Profile...", systemImage: "plus")
                    }

                    Button {
                        openWindow(id: "profiles-window")
                        NSApp.activate(ignoringOtherApps: true)
                    } label: {
                        Label("Manage Profiles...", systemImage: "slider.horizontal.3")
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: pluginManager.selectedProfileId != nil ? "person.crop.circle.fill" : "person.crop.circle")
                            .font(.title2)
                            .foregroundStyle(pluginManager.selectedProfileId != nil ? .blue : .secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(currentProfile?.name ?? "None / Custom")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundStyle(.primary)

                            Text("\(totalActiveAddons) add-ons active")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 10)

                        // Distinct Interactive Dropdown Chevron Pill
                        HStack(spacing: 2) {
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(minWidth: 220)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isHovered ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.18), lineWidth: isHovered ? 1.5 : 1)
                    )
                    .shadow(color: isHovered ? Color.accentColor.opacity(0.15) : Color.clear, radius: 4, x: 0, y: 1)
                }
                .menuStyle(.borderlessButton)
                .onHover { isHovered = $0 }
                .help("Click to switch or select a profile")
            }

            // Status Badges
            if pluginManager.selectedProfileId != nil && pluginManager.isCurrentProfileModified {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                    Text("Modified")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.15))
                .clipShape(Capsule())
            }

            if hasMissingAddons {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                    Text("Missing Add-ons")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.15))
                .foregroundStyle(.red)
                .clipShape(Capsule())
                .help("Some add-ons configured in this profile were not found in central storage.")
            }

            if let report = pluginManager.diagnosticsReport, !report.isClean {
                let isCrit = report.criticalCount > 0
                HStack(spacing: 4) {
                    Image(systemName: isCrit ? "cross.case.fill" : "cross.case")
                        .font(.caption2)
                    Text("\(report.issues.count) Diagnostics Issue\(report.issues.count > 1 ? "s" : "")")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isCrit ? Color.red.opacity(0.15) : Color.orange.opacity(0.15))
                .foregroundStyle(isCrit ? .red : .orange)
                .clipShape(Capsule())
                .help("Diagnostics detected conflicts or issues with installed scenery/add-ons.")
            }

            Spacer()

            // Quick Actions
            HStack(spacing: 8) {
                Button(action: {
                    if let selectedId = pluginManager.selectedProfileId,
                       let profile = pluginManager.profiles.first(where: { $0.id == selectedId }) {
                        pluginManager.updateProfile(profile)
                    }
                }) {
                    Label("Update", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(pluginManager.selectedProfileId == nil || !pluginManager.isCurrentProfileModified)
                .help("Update current profile with current active selection")

                Button(action: {
                    newProfileName = ""
                    showingSaveProfileAlert = true
                }) {
                    Label("Save New", systemImage: "plus")
                }
                .help("Save current selection as a new profile")

                Button(action: {
                    openWindow(id: "profiles-window")
                    NSApp.activate(ignoringOtherApps: true)
                }) {
                    Label("Manage", systemImage: "slider.horizontal.3")
                }
                .help("Open Profile Manager Window")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .alert("Save Profile", isPresented: $showingSaveProfileAlert) {
            TextField("Profile Name", text: $newProfileName)
            Button("Save") {
                if !newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    pluginManager.saveProfile(name: newProfileName)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Enter a name for this configuration.")
        }
    }
}

