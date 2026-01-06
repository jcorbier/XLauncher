import SwiftUI

@main
struct XPlaneLauncherApp: App {
    @State private var pluginManager = PluginManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(pluginManager)
                .frame(minWidth: 600, minHeight: 500)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar) // Modern look
    }
}
