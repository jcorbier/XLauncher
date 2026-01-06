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

struct ConfigurationView: View {
    @Environment(PluginManager.self) var pluginManager
    @State private var showingSaveProfileAlert = false
    @State private var newProfileName = ""
    
    var body: some View {
        @Bindable var pluginManager = pluginManager
        
        VStack(spacing: 12) {
            // Path Selection Row
            HStack {
                if let path = pluginManager.xPlanePath {
                    VStack(alignment: .leading) {
                        Text("X-Plane Location:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(path.path)
                            .font(.subheadline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } else {
                    Text("Please select your X-Plane 12 folder")
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button("Change...") {
                    selectFolder()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Material.bar)
            .cornerRadius(10)
            
            // Profile Selection Row
            HStack {
                Text("Profile:")
                    .font(.body)
                
                Picker("", selection: $pluginManager.selectedProfileId) {
                    Text("None / Custom").tag(UUID?.none)
                    Divider()
                    ForEach(pluginManager.profiles) { profile in
                        let name = (pluginManager.selectedProfileId == profile.id && pluginManager.isCurrentProfileModified) ? "\(profile.name) *" : profile.name
                        Text(name).tag(Optional(profile.id))
                    }
                }
                .frame(width: 200)
                
                Button(action: {
                    if let selectedId = pluginManager.selectedProfileId,
                       let profile = pluginManager.profiles.first(where: { $0.id == selectedId }) {
                        pluginManager.updateProfile(profile)
                    }
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .help("Update current profile with selected plugins")
                .disabled(pluginManager.selectedProfileId == nil || !pluginManager.isCurrentProfileModified)
                
                Button(action: {
                    if let selectedId = pluginManager.selectedProfileId,
                       let profile = pluginManager.profiles.first(where: { $0.id == selectedId }) {
                        pluginManager.deleteProfile(profile)
                    }
                }) {
                    Image(systemName: "trash")
                }
                .help("Delete selected profile")
                .disabled(pluginManager.selectedProfileId == nil)
                
                Button(action: {
                    newProfileName = ""
                    showingSaveProfileAlert = true
                }) {
                    Image(systemName: "plus")
                }
                .help("Save current selection as new profile")
                
                Spacer()
            }
            .padding(.horizontal)
            
            // Profile Details (Shell Script)
            if let selectedId = pluginManager.selectedProfileId,
               let profile = pluginManager.profiles.first(where: { $0.id == selectedId }) {
                
                HStack {
                    Text("Shell Script:")
                        .font(.body)
                    
                    if let scriptPath = profile.shellScriptPath, !scriptPath.isEmpty {
                        Text(URL(fileURLWithPath: scriptPath).lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(scriptPath)
                    } else {
                        Text("None")
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Select...") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = false
                        panel.allowsMultipleSelection = false
                        panel.prompt = "Select Shell Script"
                        
                        if panel.runModal() == .OK, let url = panel.url {
                            var updatedProfile = profile
                            updatedProfile.shellScriptPath = url.path
                            pluginManager.updateProfile(updatedProfile)
                        }
                    }
                    
                    if profile.shellScriptPath != nil {
                        Button("Clear") {
                            var updatedProfile = profile
                            updatedProfile.shellScriptPath = nil
                            pluginManager.updateProfile(updatedProfile)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .alert("Save Profile", isPresented: $showingSaveProfileAlert) {
            TextField("Profile Name", text: $newProfileName)
            Button("Save") {
                if !newProfileName.isEmpty {
                    pluginManager.saveProfile(name: newProfileName)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Enter a name for this configuration.")
        }
    }
    
    private func selectFolder() {
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
