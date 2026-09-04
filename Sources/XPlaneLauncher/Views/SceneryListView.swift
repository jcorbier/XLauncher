//
//  Copyright (c) 2026 Jeremie Corbier
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import SwiftUI
import UniformTypeIdentifiers

struct SceneryListView: View {
    @Environment(PluginManager.self) var pluginManager
    @State private var selection = Set<UUID>()
    @State private var isCreatingGroup = false
    @State private var newGroupName = ""
    @State private var itemToDelete: PluginManager.Scenery? = nil

    var body: some View {
        List(selection: $selection) {
            ForEach(displayItems) { item in
                switch item {
                case .group(let group, let members):
                    SceneryGroupSection(group: group, members: members, selection: selection, onDelete: {
                        itemToDelete = $0
                    }, onCreateGroup: {
                        newGroupName = ""
                        isCreatingGroup = true
                    })
                case .simple(let scenery):
                    SceneryRow(item: scenery, selection: selection, onDelete: {
                        itemToDelete = scenery
                    }, onCreateGroup: {
                        newGroupName = ""
                        isCreatingGroup = true
                    })
                        .tag(scenery.id)
                        .draggable(scenery.id.uuidString)
                }
            }
            .onMove(perform: moveDisplayItems)

            if pluginManager.scenery.isEmpty {
                ContentUnavailableView {
                    Label("No Scenery Found", systemImage: "map")
                } description: {
                    Text("Check your Central Data Folder ('Scenery' subfolder).")
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .alert("New Group", isPresented: $isCreatingGroup) {
            TextField("Group Name", text: $newGroupName)
            Button("Cancel", role: .cancel) { }
            Button("Create") {
                createGroupFromSelection()
            }
        } message: {
            Text("Enter a name for the new scenery group.")
        }
        .alert(
            "Delete Scenery",
            isPresented: Binding(
                get: { itemToDelete != nil },
                set: { if !$0 { itemToDelete = nil } }
            ),
            presenting: itemToDelete
        ) { item in
            Button("Delete", role: .destructive) {
                pluginManager.deleteScenery(item)
            }
            Button("Cancel", role: .cancel) { }
        } message: { item in
            Text("Are you sure you want to delete '\(item.name)'?\n\nThis will permanently delete the files from your Central Data Folder ('Scenery/\(item.folderName)'), unlink it from X-Plane, remove it from scenery_packs.ini, and remove it from all profiles.\n\nThis action cannot be undone.")
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
    let selection: Set<UUID>
    var onDelete: ((PluginManager.Scenery) -> Void)? = nil
    var onCreateGroup: (() -> Void)? = nil

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
                SceneryRow(item: item, selection: selection, onDelete: {
                    onDelete?(item)
                }, onCreateGroup: onCreateGroup)
                    .padding(.leading, 8)
                    .tag(item.id)
                    .draggable(item.id.uuidString)
            }
            .onMove(perform: moveMembers)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                Text(group.name)
                    .font(.headline)

                if !group.isExpanded && members.contains(where: { pluginManager.isSceneryModified($0) }) {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 5, height: 5)
                        Text("Modified")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
                }

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
        var didMove = false
        var itemsToMove: [PluginManager.Scenery] = []
        var potentialUUIDs = Set<UUID>()

        // 1. Collect dropped UUIDs
        for uuidString in items {
            if let uuid = UUID(uuidString: uuidString) {
                potentialUUIDs.insert(uuid)
            }
        }

        // 2. Check overlap with selection
        // If the dropped items are part of the selection, move the whole selection
        if !selection.isDisjoint(with: potentialUUIDs) {
            potentialUUIDs.formUnion(selection)
        }

        // 3. Resolve to Scenery objects
        for uuid in potentialUUIDs {
            if let sceneryItem = pluginManager.scenery.first(where: { $0.id == uuid }) {
                // Check if already in this group
                if !group.childFolderNames.contains(sceneryItem.folderName) {
                    itemsToMove.append(sceneryItem)
                }
            }
        }

        if !itemsToMove.isEmpty {
            DispatchQueue.main.async {
                withAnimation {
                    pluginManager.moveSceneryToGroup(items: itemsToMove, group: group)
                }
            }
            didMove = true
        }

        return didMove
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
    let selection: Set<UUID>
    var onDelete: (() -> Void)? = nil
    var onCreateGroup: (() -> Void)? = nil

    private var isOffline: Bool {
        pluginManager.isSceneryOffline(item)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.isEnabled && !isOffline ? "map.fill" : "map")
                .font(.title3)
                .foregroundStyle(item.isEnabled && !isOffline ? .green : .secondary)
                .frame(width: 32, height: 32)
                .background(item.isEnabled && !isOffline ? Color.green.opacity(0.12) : Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.body)
                        .fontWeight(.medium)

                    if isOffline {
                        HStack(spacing: 3) {
                            Image(systemName: "externaldrive.badge.xmark")
                            Text("Offline")
                        }
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.12))
                        .foregroundStyle(.red)
                        .clipShape(Capsule())
                    }

                    if let poolName = item.storagePoolName, pluginManager.storagePools.count > 1 {
                        Text(poolName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color(NSColor.windowBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                Text(item.folderName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if pluginManager.isSceneryModified(item) {
                HStack(spacing: 3) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 5, height: 5)
                    Text("Modified")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.12))
                .clipShape(Capsule())
            }

            if isOffline {
                Text("Offline")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.red.opacity(0.12))
                    .clipShape(Capsule())
            } else {
                Text(item.isEnabled ? "Enabled" : "Disabled")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(item.isEnabled ? .green : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(item.isEnabled ? Color.green.opacity(0.12) : Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }

            Toggle("", isOn: Binding(
                get: { item.isEnabled && !isOffline },
                set: { _ in pluginManager.toggleScenery(item) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(!item.isToggleable || isOffline)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
        .contextMenu {
            if !selection.isEmpty {
                Button("Create Group from Selection...", systemImage: "folder.badge.plus") {
                    onCreateGroup?()
                }
            }
            if pluginManager.sceneryGroups.contains(where: { $0.childFolderNames.contains(item.folderName) }) {
                Button("Remove from Group") {
                    pluginManager.removeFromGroup(item)
                }
            }
            if item.isManaged && !isOffline {
                Button(role: .destructive) {
                    onDelete?()
                } label: {
                    Label("Delete Add-on...", systemImage: "trash")
                }
            }
        }
        .deleteDisabled(!item.isManaged || isOffline)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, location in
            var itemsToMove: [PluginManager.Scenery] = []
            var potentialUUIDs = Set<UUID>()

            // 1. Collect dropped UUIDs
            for uuidString in items {
                if let uuid = UUID(uuidString: uuidString) {
                    potentialUUIDs.insert(uuid)
                }
            }

            // 2. Overlap with selection
            if !selection.isDisjoint(with: potentialUUIDs) {
                 potentialUUIDs.formUnion(selection)
            }

            // 3. Resolve
            for uuid in potentialUUIDs {
                if let sceneryItem = pluginManager.scenery.first(where: { $0.id == uuid }) {
                    itemsToMove.append(sceneryItem)
                }
            }

            if !itemsToMove.isEmpty {
                DispatchQueue.main.async {
                    withAnimation {
                        pluginManager.moveScenery(items: itemsToMove, relativeTo: item)
                    }
                }
                return true
            }
            return false
        }
    }
}
