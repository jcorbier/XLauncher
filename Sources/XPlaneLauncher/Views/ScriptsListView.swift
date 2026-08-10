import SwiftUI

struct ScriptsListView: View {
    @Environment(PluginManager.self) var pluginManager
    @State private var showingFileImporter = false
    @State private var selectedEnvVarId: PluginManager.ScriptEnvVar.ID?
    
    var body: some View {
        @Bindable var pluginManager = pluginManager
        
        VStack(spacing: 12) {
            if pluginManager.selectedProfileId != nil {
                HSplitView {
                    // Profile Scripts Column
                    GroupBox("Profile Scripts") {
                        VStack(spacing: 0) {
                            List {
                                ForEach(pluginManager.activeScripts) { script in
                                    ScriptRow(script: script)
                                }
                                .onDelete(perform: deleteItems)
                                
                                if pluginManager.activeScripts.isEmpty {
                                    ContentUnavailableView {
                                        Label("No Scripts", systemImage: "terminal")
                                    } description: {
                                        Text("Add shell scripts to execute when launching this profile.")
                                    }
                                }
                            }
                            .listStyle(.inset)
                            .scrollContentBackground(.hidden)
                            
                            HStack {
                                Button(action: { showingFileImporter = true }) {
                                    Label("Add Script", systemImage: "plus")
                                }
                                Spacer()
                            }
                            .padding(.top, 8)
                        }
                        .padding(8)
                    }
                    .frame(minWidth: 250)
                    
                    // Profile Environment Variables Column
                    GroupBox("Profile Environment Variables") {
                        VStack(spacing: 0) {
                            Table($pluginManager.activeEnvironmentVariables, selection: $selectedEnvVarId) {
                                TableColumn("Key") { $envVar in
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
                            .scrollContentBackground(.hidden)
                            .background(Color(NSColor.controlBackgroundColor))
                            .border(Color(NSColor.separatorColor), width: 1)
                            
                            HStack {
                                Button(action: {
                                    pluginManager.addProfileEnvVar()
                                }) {
                                    Image(systemName: "plus")
                                        .frame(width: 20, height: 20)
                                }
                                
                                Button(action: {
                                    if let selectedId = selectedEnvVarId {
                                        pluginManager.deleteProfileEnvVar(id: selectedId)
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
                    .frame(minWidth: 250)
                }
                .padding()
            } else {
                ContentUnavailableView {
                    Label("No Profile Selected", systemImage: "person.crop.circle.badge.exclamationmark")
                } description: {
                    Text("Select a profile to manage scripts and environment variables.")
                }
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.shellScript, .plainText],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for url in urls {
                    pluginManager.addScript(name: url.lastPathComponent, path: url.path)
                }
            case .failure(let error):
                print("Failed to import script: \(error.localizedDescription)")
            }
        }
    }
    
    func deleteItems(at offsets: IndexSet) {
        offsets.forEach { index in
            let script = pluginManager.activeScripts[index]
            pluginManager.deleteScript(script)
        }
    }
}

struct ScriptRow: View {
    @Environment(PluginManager.self) var pluginManager
    let script: PluginManager.ProfileScript
    
    var body: some View {
        HStack {
            Image(systemName: "terminal.fill")
                .foregroundStyle(script.isEnabled ? .green : .secondary)
            
            VStack(alignment: .leading) {
                Text(URL(fileURLWithPath: script.path).lastPathComponent)
                    .font(.body)
                Text(script.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .truncationMode(.middle)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { script.isEnabled },
                set: { _ in pluginManager.toggleScript(script) }
            ))
            .toggleStyle(.switch)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Delete", role: .destructive) {
                pluginManager.deleteScript(script)
            }
        }
    }
}
