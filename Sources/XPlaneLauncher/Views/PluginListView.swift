import SwiftUI

struct PluginListView: View {
    @Environment(PluginManager.self) var pluginManager
    
    // Sort logic handled in manager, or here. Manager is cleaner.
    
    var body: some View {
        List {
            ForEach(pluginManager.plugins) { plugin in
                PluginRow(plugin: plugin)
            }
            
            if pluginManager.plugins.isEmpty {
                ContentUnavailableView {
                    Label("No Plugins Found", systemImage: "puzzlepiece.extension")
                } description: {
                    Text("Check your X-Plane 'Resources/available plugins' folder.")
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }
}

struct PluginRow: View {
    @Environment(PluginManager.self) var pluginManager
    let plugin: PluginManager.Plugin
    
    var body: some View {
        HStack {
            Image(systemName: "puzzlepiece.fill")
                .foregroundStyle(plugin.isEnabled ? .green : .secondary)
            
            Text(plugin.name)
                .font(.body)
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { plugin.isEnabled },
                set: { _ in pluginManager.togglePlugin(plugin) }
            ))
            .toggleStyle(.switch)
        }
        .padding(.vertical, 4)
    }
}
