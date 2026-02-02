//
//  ScriptsListView.swift
//  XPlaneLauncher
//
//  Created for Script Management
//

import SwiftUI

struct ScriptsListView: View {
    @Environment(PluginManager.self) var pluginManager
    @State private var showingFileImporter = false
    
    // Sort logic handled in manager, or here. Manager is cleaner.
    
    var currentProfile: PluginManager.PluginProfile? {
        guard let id = pluginManager.selectedProfileId else { return nil }
        return pluginManager.profiles.first(where: { $0.id == id })
    }
    
    var body: some View {
        VStack {
            if pluginManager.selectedProfileId != nil {
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
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: { showingFileImporter = true }) {
                            Label("Add Script", systemImage: "plus")
                        }
                    }
                }
            } else {
                 ContentUnavailableView {
                    Label("No Profile Selected", systemImage: "person.crop.circle.badge.exclamationmark")
                } description: {
                    Text("Select a profile to manage scripts.")
                }
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.shellScript, .plainText], // Adjust as needed
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
