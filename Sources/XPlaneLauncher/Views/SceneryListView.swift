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
            Image(systemName: "map.fill")
                .foregroundStyle(item.isEnabled ? .green : .secondary)
            
            Text(item.name)
                .font(.body)
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { item.isEnabled },
                set: { _ in pluginManager.toggleScenery(item) }
            ))
            .toggleStyle(.switch)
        }
        .padding(.vertical, 4)
    }
}
