import SwiftUI

struct ContentView: View {
    @Environment(PluginManager.self) var pluginManager
    
    var body: some View {
        VStack(spacing: 0) {
            // Header / Config
            ConfigurationView()
                .padding()
            
            Divider()
            
            // Main List
            PluginListView()
                .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Footer Action
            VStack {
                LaunchButton()
            }
            .padding()
            .background(Material.bar)
        }
    }
}
