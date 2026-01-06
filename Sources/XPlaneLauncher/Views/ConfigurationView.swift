import SwiftUI

struct ConfigurationView: View {
    @Environment(PluginManager.self) var pluginManager
    @State private var showingSaveProfileAlert = false
    @State private var newProfileName = ""
    
    var body: some View {
        @Bindable var pluginManager = pluginManager
        
        VStack(spacing: 12) {
            // Path Selection Row
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
            
            // Profile Selection Row
            HStack {
                Text("Profile:")
                    .font(.body)
                
                Picker("", selection: $pluginManager.selectedProfileId) {
                    Text("None / Custom").tag(UUID?.none)
                    Divider()
                    ForEach(pluginManager.profiles) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }
                .frame(width: 200)
                
                Button(action: {
                    newProfileName = ""
                    showingSaveProfileAlert = true
                }) {
                    Image(systemName: "plus")
                }
                .help("Save current selection as new profile")
                
                Spacer()
            }
            .padding(.horizontal)
        }
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
