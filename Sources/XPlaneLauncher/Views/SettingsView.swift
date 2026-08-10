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

struct SettingsView: View {
    @Environment(PluginManager.self) var pluginManager
    @State private var selectedEnvVarId: PluginManager.ScriptEnvVar.ID?
    
    var body: some View {
        @Bindable var pluginManager = pluginManager
        
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
                        }
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
    }
}
