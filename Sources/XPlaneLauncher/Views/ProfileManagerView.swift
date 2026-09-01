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

struct ProfileManagerView: View {
    @Environment(PluginManager.self) var pluginManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProfileId: UUID? = nil
    @State private var searchText: String = ""
    @State private var showingNewProfileAlert: Bool = false
    @State private var newProfileName: String = ""
    @State private var showingRenameAlert: Bool = false
    @State private var renameTargetProfile: PluginProfile? = nil
    @State private var renameTargetName: String = ""
    @State private var profileToDelete: PluginProfile? = nil
    @State private var showingDeleteConfirmation: Bool = false
    @State private var statusMessage: String? = nil

    private var filteredProfiles: [PluginProfile] {
        if searchText.isEmpty {
            return pluginManager.profiles
        }
        return pluginManager.profiles.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedProfile: PluginProfile? {
        if let id = selectedProfileId {
            return pluginManager.profiles.first(where: { $0.id == id })
        }
        return pluginManager.profiles.first
    }

    var body: some View {
        @Bindable var pluginManager = pluginManager

        VStack(spacing: 0) {
            // Header Bar
            HStack {
                Label("Profile Manager", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Main Split Content
            HSplitView {
                // Left Master List
                VStack(spacing: 0) {
                    // Search & Actions
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search profiles...", text: $searchText)
                            .textFieldStyle(.plain)

                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    // Profiles List
                    if filteredProfiles.isEmpty {
                        VStack(spacing: 8) {
                            Spacer()
                            Image(systemName: "person.crop.circle.badge.questionmark")
                                .font(.system(size: 32))
                                .foregroundStyle(.tertiary)
                            Text(pluginManager.profiles.isEmpty ? "No profiles saved yet." : "No matching profiles.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(selection: $selectedProfileId) {
                            ForEach(filteredProfiles) { profile in
                                profileRow(for: profile)
                                    .tag(profile.id)
                                    .contextMenu {
                                        Button {
                                            pluginManager.activateProfile(profile)
                                        } label: {
                                            Label("Activate", systemImage: "checkmark.circle")
                                        }

                                        Button {
                                            pluginManager.duplicateProfile(profile)
                                        } label: {
                                            Label("Duplicate", systemImage: "doc.on.doc")
                                        }

                                        Button {
                                            renameTargetProfile = profile
                                            renameTargetName = profile.name
                                            showingRenameAlert = true
                                        } label: {
                                            Label("Rename...", systemImage: "pencil")
                                        }

                                        Button {
                                            exportProfile(profile)
                                        } label: {
                                            Label("Export JSON...", systemImage: "square.and.arrow.up")
                                        }

                                        Divider()

                                        Button(role: .destructive) {
                                            profileToDelete = profile
                                            showingDeleteConfirmation = true
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                            .onMove { source, destination in
                                pluginManager.reorderProfiles(fromOffsets: source, toOffset: destination)
                            }
                        }
                        .listStyle(.sidebar)
                    }

                    Divider()

                    // Bottom Action Toolbar
                    HStack(spacing: 6) {
                        Button(action: {
                            newProfileName = ""
                            showingNewProfileAlert = true
                        }) {
                            Image(systemName: "plus")
                        }
                        .help("Create New Profile")

                        Menu {
                            Button {
                                pluginManager.sortProfiles(by: .nameAsc)
                            } label: {
                                Label("Name (A-Z)", systemImage: "arrow.up")
                            }

                            Button {
                                pluginManager.sortProfiles(by: .nameDesc)
                            } label: {
                                Label("Name (Z-A)", systemImage: "arrow.down")
                            }

                            Button {
                                pluginManager.sortProfiles(by: .mostAddons)
                            } label: {
                                Label("Most Add-ons", systemImage: "number")
                            }

                            Button {
                                pluginManager.sortProfiles(by: .leastAddons)
                            } label: {
                                Label("Least Add-ons", systemImage: "number")
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 24)
                        .help("Sort Profiles")

                        Spacer()

                        Button("Import...") {
                            importProfiles()
                        }
                        .font(.caption)
                        .help("Import profile JSON")

                        Button("Export All...") {
                            exportAllProfiles()
                        }
                        .font(.caption)
                        .disabled(pluginManager.profiles.isEmpty)
                        .help("Export all profiles to JSON")
                    }
                    .padding(8)
                    .background(Color(NSColor.windowBackgroundColor))
                }
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)

                // Right Detail Inspector Pane
                Group {
                    if let selected = selectedProfile {
                        ProfileInspectorView(profile: selected)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 48))
                                .foregroundStyle(.tertiary)
                            Text("Select or create a profile to inspect its details.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 460)
            }

            // Optional Status Message
            if let status = statusMessage {
                HStack {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Dismiss") {
                        statusMessage = nil
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
            }
        }
        .frame(minWidth: 780, minHeight: 520)
        .onAppear {
            if selectedProfileId == nil {
                selectedProfileId = pluginManager.selectedProfileId ?? pluginManager.profiles.first?.id
            }
        }
        .alert("New Profile", isPresented: $showingNewProfileAlert) {
            TextField("Profile Name", text: $newProfileName)
            Button("Create") {
                if !newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    pluginManager.saveProfile(name: newProfileName)
                    selectedProfileId = pluginManager.selectedProfileId
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Enter a name for the new profile based on your current add-on configuration.")
        }
        .alert("Rename Profile", isPresented: $showingRenameAlert) {
            TextField("New Name", text: $renameTargetName)
            Button("Rename") {
                if let target = renameTargetProfile, !renameTargetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    pluginManager.renameProfile(target, newName: renameTargetName)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Enter a new name for profile '\(renameTargetProfile?.name ?? "")'.")
        }
        .confirmationDialog(
            "Delete Profile",
            isPresented: $showingDeleteConfirmation,
            presenting: profileToDelete
        ) { profile in
            Button("Delete '\(profile.name)'", role: .destructive) {
                pluginManager.deleteProfile(profile)
                if selectedProfileId == profile.id {
                    selectedProfileId = pluginManager.profiles.first?.id
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: { profile in
            Text("Are you sure you want to delete profile '\(profile.name)'? This action cannot be undone.")
        }
    }

    // MARK: - Row View

    private func profileRow(for profile: PluginProfile) -> some View {
        let isActive = pluginManager.selectedProfileId == profile.id
        let hasMissing = pluginManager.hasMissingAddons(for: profile)
        let totalAddons = profile.aircraftFolderNames.count + profile.pluginFolderNames.count + profile.sceneryFolderNames.count + profile.luaScriptFolderNames.count

        return HStack(spacing: 8) {
            Image(systemName: isActive ? "person.crop.circle.fill" : "person.crop.circle")
                .font(.title3)
                .foregroundStyle(isActive ? .blue : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(profile.name)
                        .font(.body)
                        .fontWeight(isActive ? .bold : .regular)

                    if isActive {
                        Text("Active")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }

                    if hasMissing {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }

                Text("\(totalAddons) add-ons • \(profile.scripts.count) scripts")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 3)
    }

    // MARK: - File Export / Import Helpers

    private func exportProfile(_ profile: PluginProfile) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let sanitized = profile.name.replacingOccurrences(of: "/", with: "_")
        panel.nameFieldStringValue = "\(sanitized).json"
        panel.prompt = "Export Profile"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try pluginManager.exportProfile(profile, to: url)
                statusMessage = "Exported '\(profile.name)' successfully."
            } catch {
                statusMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    private func exportAllProfiles() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "XLauncher_Profiles.json"
        panel.prompt = "Export All Profiles"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try pluginManager.exportAllProfiles(to: url)
                statusMessage = "Exported \(pluginManager.profiles.count) profiles successfully."
            } catch {
                statusMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    private func importProfiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Import Profile"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let imported = try pluginManager.importProfiles(from: url)
                if let first = imported.first {
                    selectedProfileId = first.id
                }
                statusMessage = "Imported \(imported.count) profile(s) successfully."
            } catch {
                statusMessage = "Import failed: \(error.localizedDescription)"
            }
        }
    }
}
