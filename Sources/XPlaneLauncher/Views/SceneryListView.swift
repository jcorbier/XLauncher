//
//  MIT License
//  Copyright (c) 2026 Jeremie Corbier
//

import SwiftUI
import UniformTypeIdentifiers

struct SceneryListView: View {
    @Environment(PluginManager.self) var pluginManager
    @State private var selection = Set<UUID>()
    @State private var isCreatingGroup = false
    @State private var newGroupName = ""
    
    var body: some View {
        NavigationStack {
            List(selection: $selection) {
                ForEach(displayItems) { item in
                    switch item {
                    case .group(let group, let members):
                        SceneryGroupSection(group: group, members: members)
                    case .simple(let scenery):
                        SceneryRow(item: scenery)
                            .tag(scenery.id)
                            .draggable(scenery.id.uuidString)
                    }
                }
                .onMove(perform: moveDisplayItems)
                
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
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Create Group", systemImage: "folder.badge.plus") {
                        newGroupName = ""
                        isCreatingGroup = true
                    }
                    .disabled(selection.isEmpty)
                }
            }
            .alert("New Group", isPresented: $isCreatingGroup) {
                TextField("Group Name", text: $newGroupName)
                Button("Cancel", role: .cancel) { }
                Button("Create") {
                    createGroupFromSelection()
                }
            } message: {
                Text("Enter a name for the new scenery group.")
            }
        }
    }
    
    // MARK: - Data Source
    
    enum DisplayItem: Identifiable {
        case simple(PluginManager.Scenery)
        case group(PluginManager.SceneryGroup, [PluginManager.Scenery])
        
        var id: UUID {
            switch self {
            case .simple(let s): return s.id
            case .group(let g, _): return g.id
            }
        }
    }
    
    var displayItems: [DisplayItem] {
        var items: [DisplayItem] = []
        var processedGroups = Set<UUID>()
        
        for item in pluginManager.scenery {
            // Check if item belongs to a group
            if let group = pluginManager.sceneryGroups.first(where: { $0.childFolderNames.contains(item.folderName) }) {
                if !processedGroups.contains(group.id) {
                    // Start of a group
                    // Gather all members from the pluginManager.scenery list that belong to this group
                    // Note: We use the order from the main list to respect load order, filtering for this group's members
                    let members = pluginManager.scenery.filter { group.childFolderNames.contains($0.folderName) }
                    items.append(.group(group, members))
                    processedGroups.insert(group.id)
                }
                // Else, already handled this group
            } else {
                items.append(.simple(item))
            }
        }
        return items
    }
    
    // MARK: - Actions
    
    func createGroupFromSelection() {
        let selectedItems = pluginManager.scenery.filter { selection.contains($0.id) }
        guard !selectedItems.isEmpty else { return }
        
        pluginManager.createGroup(name: newGroupName, with: selectedItems)
        selection.removeAll()
    }
    
    func moveDisplayItems(from source: IndexSet, to destination: Int) {
        var currentDisplay = displayItems
        currentDisplay.move(fromOffsets: source, toOffset: destination)
        
        var newScenery: [PluginManager.Scenery] = []
        for item in currentDisplay {
             switch item {
             case .simple(let s): newScenery.append(s)
             case .group(_, let members): newScenery.append(contentsOf: members)
             }
        }
        
        pluginManager.scenery = newScenery
        pluginManager.saveSceneryOrder()
    }
}

// MARK: - Subviews

struct SceneryGroupSection: View {
    @Environment(PluginManager.self) var pluginManager
    let group: PluginManager.SceneryGroup
    let members: [PluginManager.Scenery]
    
    @State private var isRenaming = false
    @State private var renameText = ""
    
    var body: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { group.isExpanded },
            set: { isExpanded in
                if let idx = pluginManager.sceneryGroups.firstIndex(where: { $0.id == group.id }) {
                    pluginManager.sceneryGroups[idx].isExpanded = isExpanded
                }
            }
        )) {
            ForEach(members) { item in
                SceneryRow(item: item)
                    .padding(.leading, 8)
                    .draggable(item.id.uuidString)
            }
            .onMove(perform: moveMembers)
        } label: {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                Text(group.name)
                    .font(.headline)
                Spacer()
                
                // Group Toggles
                Toggle("", isOn: Binding(
                    get: { members.contains(where: { $0.isEnabled }) }, // On if any is on? Or all? User req: Toggle group toggles all.
                    set: { newVal in
                        pluginManager.toggleGroup(group, isEnabled: newVal)
                    }
                ))
                .toggleStyle(.switch)
            }
            .contentShape(Rectangle()) // Make entire header droppable
            .dropDestination(for: String.self) { items, location in
                return handleDrop(items: items)
            }
            .contextMenu {
                Button("Rename...", systemImage: "pencil") {
                    renameText = group.name
                    isRenaming = true
                }
                Button("Delete Group", systemImage: "trash", role: .destructive) {
                    pluginManager.deleteGroup(group)
                }
            }
            .alert("Rename Group", isPresented: $isRenaming) {
                TextField("New Name", text: $renameText)
                Button("Cancel", role: .cancel) { }
                Button("Rename") {
                    pluginManager.renameGroup(group, newName: renameText)
                }
            }
        }
    }
    
    func handleDrop(items: [String]) -> Bool {
        guard let uuidString = items.first, let uuid = UUID(uuidString: uuidString) else { return false }
        
        if let sceneryItem = pluginManager.scenery.first(where: { $0.id == uuid }) {
            // Check if already in this group
            if group.childFolderNames.contains(sceneryItem.folderName) {
                return false
            }
            
            withAnimation {
                pluginManager.moveSceneryToGroup(sceneryItem, group: group)
            }
            return true
        }
        return false
    }
    
    func moveMembers(from source: IndexSet, to destination: Int) {
        // Reorder members within the group
        var currentMembers = members
        currentMembers.move(fromOffsets: source, toOffset: destination)
        
        // Reconstruct global list
        if let firstOld = members.first,
           let insertIndex = pluginManager.scenery.firstIndex(where: { $0.id == firstOld.id }) {
             
             var _ = pluginManager.scenery.filter { !group.childFolderNames.contains($0.folderName) }
             
             var allScenery = pluginManager.scenery
             allScenery.removeAll { group.childFolderNames.contains($0.folderName) }
             
             let safeIndex = min(insertIndex, allScenery.count)
             
             allScenery.insert(contentsOf: currentMembers, at: safeIndex)
             
             pluginManager.scenery = allScenery
             pluginManager.saveSceneryOrder()
        }
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
                     Text("New (Unmanaged)")
                        .font(.caption)
                        .foregroundStyle(.blue)
                } else if !item.isInIni && item.isEnabled {
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
                .disabled(!item.isToggleable)
            } else {
                Button("Install") {
                    pluginManager.toggleScenery(item)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            // Add "Remove from Group" if in group
            if pluginManager.sceneryGroups.contains(where: { $0.childFolderNames.contains(item.folderName) }) {
                Button("Remove from Group") {
                    pluginManager.removeFromGroup(item)
                }
            }
        }
        .deleteDisabled(!item.isManaged)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, location in
            guard let uuidString = items.first, let uuid = UUID(uuidString: uuidString) else { return false }
            guard let sourceItem = pluginManager.scenery.first(where: { $0.id == uuid }) else { return false }
            
            // Move sourceItem relative to 'item' (this row)
            withAnimation {
                pluginManager.moveScenery(sourceItem, relativeTo: item)
            }
            return true
        }
    }
    
    var statusColor: Color {
        if item.isEnabled { return .green }
        if item.isInIni { return .orange }
        return .secondary
    }
}
