import SwiftUI

struct ConfigurationView: View {
    @Environment(PluginManager.self) var pluginManager
    
    var body: some View {
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
