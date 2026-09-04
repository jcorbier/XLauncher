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

struct AircraftListView: View {
    @Environment(PluginManager.self) var pluginManager
    @State private var itemToDelete: PluginManager.Aircraft? = nil
    @State private var taggingAircraft: PluginManager.Aircraft? = nil
    @State private var searchText: String = ""
    @State private var selectedCategory: AircraftCategory? = nil
    @State private var selectedTag: String = "All"

    private var allKnownTags: [String] {
        ["All"] + pluginManager.allKnownTags(for: "aircraft:")
    }

    private var filteredAircraft: [PluginManager.Aircraft] {
        var list = pluginManager.aircraft

        if let cat = selectedCategory {
            list = list.filter { pluginManager.category(for: $0) == cat }
        }

        if selectedTag != "All" {
            list = list.filter {
                let tags = pluginManager.tags(for: "aircraft:\($0.folderName)")
                return tags.contains(selectedTag)
            }
        }

        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            let q = searchText.lowercased()
            list = list.filter { item in
                let catName = pluginManager.category(for: item).rawValue.lowercased()
                let tags = pluginManager.tags(for: "aircraft:\(item.folderName)").map { $0.lowercased() }
                return item.name.lowercased().contains(q) ||
                       item.folderName.lowercased().contains(q) ||
                       catName.contains(q) ||
                       tags.contains(where: { $0.contains(q) })
            }
        }

        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter & Search Bar
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search aircraft, category, tags...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(maxWidth: 260)

                Picker("Category", selection: $selectedCategory) {
                    Text("All Categories").tag(AircraftCategory?.none)
                    Divider()
                    ForEach(AircraftCategory.allCases) { cat in
                        Text(cat.rawValue).tag(AircraftCategory?.some(cat))
                    }
                }
                .frame(width: 170)

                if allKnownTags.count > 1 {
                    Picker("Tag", selection: $selectedTag) {
                        ForEach(allKnownTags, id: \.self) { tag in
                            Text(tag == "All" ? "All Tags" : tag).tag(tag)
                        }
                    }
                    .frame(width: 140)
                }

                Spacer()

                if selectedCategory != nil || selectedTag != "All" || !searchText.isEmpty {
                    Button("Reset") {
                        selectedCategory = nil
                        selectedTag = "All"
                        searchText = ""
                    }
                    .buttonStyle(.link)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            List {
                ForEach(filteredAircraft) { item in
                    AircraftRow(
                        aircraft: item,
                        onDelete: { itemToDelete = item },
                        onEditTags: { taggingAircraft = item }
                    )
                }

                if pluginManager.aircraft.isEmpty {
                    ContentUnavailableView {
                        Label("No Aircraft Found", systemImage: "airplane")
                    } description: {
                        Text("Check your Central Data Folder ('Aircraft' subfolder).")
                    }
                } else if filteredAircraft.isEmpty {
                    ContentUnavailableView("No Matching Aircraft", systemImage: "magnifyingglass", description: Text("Try adjusting your search or category filter."))
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
        .alert(
            "Delete Aircraft",
            isPresented: Binding(
                get: { itemToDelete != nil },
                set: { if !$0 { itemToDelete = nil } }
            ),
            presenting: itemToDelete
        ) { item in
            Button("Delete", role: .destructive) {
                pluginManager.deleteAircraft(item)
            }
            Button("Cancel", role: .cancel) { }
        } message: { item in
            Text("Are you sure you want to delete '\(item.name)'?\n\nThis will permanently delete the files from your Central Data Folder ('Aircraft/\(item.folderName)'), unlink it from X-Plane, and remove it from all profiles.\n\nThis action cannot be undone.")
        }
        .sheet(item: $taggingAircraft) { item in
            let cat = pluginManager.category(for: item)
            let itemKey = "aircraft:\(item.folderName)"
            EditAddonTagsSheet(
                title: item.name,
                itemKey: itemKey,
                detectedCategory: cat.rawValue,
                availableCategories: AircraftCategory.allCases.map { $0.rawValue },
                kindPrefix: "aircraft:",
                currentCustomCategory: pluginManager.addonMetadata[itemKey]?.customCategory,
                currentTags: pluginManager.tags(for: itemKey)
            )
        }
    }
}

struct AircraftRow: View {
    @Environment(PluginManager.self) var pluginManager
    let aircraft: PluginManager.Aircraft
    var onDelete: (() -> Void)? = nil
    var onEditTags: (() -> Void)? = nil

    private var isOffline: Bool {
        pluginManager.isAircraftOffline(aircraft)
    }

    private var category: AircraftCategory {
        pluginManager.category(for: aircraft)
    }

    private var tags: [String] {
        pluginManager.tags(for: "aircraft:\(aircraft.folderName)")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "airplane")
                .font(.title3)
                .foregroundStyle(aircraft.isEnabled && !isOffline ? .green : .secondary)
                .frame(width: 32, height: 32)
                .background(aircraft.isEnabled && !isOffline ? Color.green.opacity(0.12) : Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(aircraft.name)
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

                    if let poolName = aircraft.storagePoolName, pluginManager.storagePools.count > 1 {
                        Text(poolName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color(NSColor.windowBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                HStack(spacing: 6) {
                    Text(aircraft.folderName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Category badge
                    HStack(spacing: 3) {
                        Image(systemName: category.systemImage)
                            .font(.system(size: 9))
                        Text(category.rawValue)
                            .font(.system(size: 9, weight: .medium))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(category.color.opacity(0.12))
                    .foregroundStyle(category.color)
                    .clipShape(Capsule())

                    // Tag chips
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.secondary.opacity(0.12))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            if pluginManager.isAircraftModified(aircraft) {
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

            // Tag Edit Button
            Button(action: { onEditTags?() }) {
                Image(systemName: tags.isEmpty ? "tag" : "tag.fill")
                    .font(.caption)
                    .foregroundStyle(tags.isEmpty ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.borderless)
            .help("Edit Category & Tags")

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
                Text(aircraft.isEnabled ? "Enabled" : "Disabled")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(aircraft.isEnabled ? .green : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(aircraft.isEnabled ? Color.green.opacity(0.12) : Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }

            Toggle("", isOn: Binding(
                get: { aircraft.isEnabled && !isOffline },
                set: { _ in pluginManager.toggleAircraft(aircraft) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(isOffline)
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
            Button {
                onEditTags?()
            } label: {
                Label("Edit Category & Tags...", systemImage: "tag")
            }

            Divider()

            if !isOffline {
                Button(role: .destructive) {
                    onDelete?()
                } label: {
                    Label("Delete Add-on...", systemImage: "trash")
                }
            }
        }
    }
}
