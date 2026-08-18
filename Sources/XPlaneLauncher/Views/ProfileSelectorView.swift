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
    @State private var showingSaveProfileAlert = false
    @State private var newProfileName = ""
    
    var body: some View {
        @Bindable var pluginManager = pluginManager
        
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                
                Text("Profile:")
                    .font(.headline)
                
                Picker("", selection: $pluginManager.selectedProfileId) {
                    Text("None / Custom").tag(UUID?.none)
                    Divider()
                    ForEach(pluginManager.profiles) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            }
            
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
                .padding(.vertical, 3)
                .background(Color.orange.opacity(0.15))
                .clipShape(Capsule())
            }
            
            Spacer()
            
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
                .help("Update current profile with current selection")
                
                Button(action: {
                    newProfileName = ""
                    showingSaveProfileAlert = true
                }) {
                    Label("Save New", systemImage: "plus")
                }
                .help("Save current selection as a new profile")
                
                Button(action: {
                    if let selectedId = pluginManager.selectedProfileId,
                       let profile = pluginManager.profiles.first(where: { $0.id == selectedId }) {
                        pluginManager.deleteProfile(profile)
                    }
                }) {
                    Image(systemName: "trash")
                }
                .disabled(pluginManager.selectedProfileId == nil)
                .help("Delete selected profile")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
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
}
