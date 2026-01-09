//
//  MIT License
//  Copyright (c) 2026 Jeremie Corbier
//

import SwiftUI

struct SceneryListView: View {
    @Environment(PluginManager.self) var pluginManager
    
    var body: some View {
        List {
            ForEach(pluginManager.scenery) { item in
                SceneryRow(item: item)
            }
            .onMove { source, destination in
                pluginManager.moveScenery(from: source, to: destination)
            }
            .onDelete { offsets in
                for index in offsets {
                    let item = pluginManager.scenery[index]
                    pluginManager.unlinkScenery(item)
                }
            }
            
            if pluginManager.scenery.isEmpty {
                ContentUnavailableView {
                    Label("No Scenery Found", systemImage: "map")
                } description: {
                    Text("Check your 'available scenery' folder.")
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }
}

struct SceneryRow: View {
    @Environment(PluginManager.self) var pluginManager
    let item: PluginManager.Scenery
    
    var body: some View {
        HStack {
            Image(systemName: item.isEnabled ? "map.fill" : "map")
                .foregroundStyle(statusColor)
            
            VStack(alignment: .leading) {
                Text(item.name)
                    .font(.body)
                if !item.isManaged && !item.isInIni {
                     // New manual folder
                     Text("New (Unmanaged)")
                        .font(.caption)
                        .foregroundStyle(.blue)
                } else if !item.isInIni && item.isEnabled {
                    // Just added
                    Text("New")
                       .font(.caption)
                       .foregroundStyle(.blue)
                } else if !item.isEnabled && !item.isInIni {
                    Text("Not Installed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            if item.isEnabled || item.isInIni {
                Toggle("", isOn: Binding(
                    get: { item.isEnabled },
                    set: { _ in pluginManager.toggleScenery(item) }
                ))
                .toggleStyle(.switch)
            } else {
                // Install button for uninstalled items
                Button("Install") {
                    pluginManager.toggleScenery(item)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
        // Disable swipe to delete for unmanaged real folders to prevent accidents? 
        // PluginManager.unlinkScenery already guards isManaged.
        // We can hide the action UI using check:
        .deleteDisabled(!item.isManaged)
    }
    
    var statusColor: Color {
        if item.isEnabled { return .green }
        if item.isInIni { return .orange } // Disabled in INI
        return .secondary // Not installed
    }
}
