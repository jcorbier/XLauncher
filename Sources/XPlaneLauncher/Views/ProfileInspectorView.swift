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

struct ProfileInspectorView: View {
    @Environment(PluginManager.self) var pluginManager
    let profile: PluginProfile

    @State private var comparisonProfileId: UUID? = nil
    @State private var overviewSearchText: String = ""

    private var missingAddons: [AddonCategory: [String]] {
        pluginManager.missingAddons(for: profile)
    }

    private var isActive: Bool {
        pluginManager.selectedProfileId == profile.id
    }

    private var otherProfiles: [PluginProfile] {
        pluginManager.profiles.filter { $0.id != profile.id }
    }

    private var isComparing: Bool {
        comparisonProfileId != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Profile Header Summary & Compare Selector
            headerView

            Divider()

            // Main Content: Either Comparison View or Unified Overview
            if let targetId = comparisonProfileId,
               let targetProfile = pluginManager.profiles.first(where: { $0.id == targetId }) {
                diffResultsView(comparing: targetProfile)
            } else {
                overviewView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(isActive ? .blue : .secondary)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(profile.name)
                            .font(.title3)
                            .fontWeight(.bold)

                        if isActive {
                            Text("Active")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.15))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }

                        if !missingAddons.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text("\(missingAddons.values.reduce(0, { $0 + $1.count })) Missing")
                            }
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.15))
                            .foregroundStyle(.red)
                            .clipShape(Capsule())
                        }
                    }

                    HStack(spacing: 12) {
                        Label("\(profile.aircraftFolderNames.count) Aircraft", systemImage: "airplane")
                        Label("\(profile.pluginFolderNames.count) Plugins", systemImage: "puzzlepiece.extension")
                        Label("\(profile.sceneryFolderNames.count) Scenery", systemImage: "map")
                        Label("\(profile.luaScriptFolderNames.count) Lua", systemImage: "scroll")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                // Header Action Controls
                HStack(spacing: 10) {
                    // Compare with... Menu / Dropdown
                    if !otherProfiles.isEmpty {
                        Menu {
                            Section("Compare against") {
                                if isComparing {
                                    Button(role: .destructive) {
                                        comparisonProfileId = nil
                                    } label: {
                                        Label("Stop Comparing (Back to Overview)", systemImage: "xmark")
                                    }
                                    Divider()
                                }

                                ForEach(otherProfiles) { other in
                                    Button {
                                        comparisonProfileId = other.id
                                    } label: {
                                        HStack {
                                            Text(other.name)
                                            if comparisonProfileId == other.id {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "square.split.2x1")
                                    .font(.caption)
                                Text(isComparing ? "Comparing" : "Compare with...")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(isComparing ? Color.purple.opacity(0.15) : Color(NSColor.controlBackgroundColor))
                            .foregroundStyle(isComparing ? .purple : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isComparing ? Color.purple.opacity(0.4) : Color.primary.opacity(0.15), lineWidth: 1)
                            )
                        }
                        .menuStyle(.borderlessButton)
                        .help("Compare this profile side-by-side with another profile")
                    }

                    if !isActive {
                        Button(action: {
                            pluginManager.activateProfile(profile)
                        }) {
                            Label("Activate Profile", systemImage: "checkmark.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }
                }
            }

            // Comparison Active Banner
            if let targetId = comparisonProfileId,
               let targetProfile = pluginManager.profiles.first(where: { $0.id == targetId }) {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                        Text(profile.name)
                            .font(.caption)
                            .fontWeight(.bold)
                    }

                    Image(systemName: "arrow.left.and.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.purple)
                            .frame(width: 8, height: 8)
                        Text(targetProfile.name)
                            .font(.caption)
                            .fontWeight(.bold)
                    }

                    Spacer()

                    Button("Close Comparison") {
                        comparisonProfileId = nil
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.purple.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Overview View (All Addons in Category Cards)

    private var overviewView: some View {
        VStack(spacing: 0) {
            // Filter Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter add-ons in \(profile.name)...", text: $overviewSearchText)
                    .textFieldStyle(.plain)

                if !overviewSearchText.isEmpty {
                    Button(action: { overviewSearchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Missing Add-ons Alert
                    if !missingAddons.isEmpty {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.red)
                                    Text("Missing Add-ons Detected")
                                        .fontWeight(.bold)
                                        .foregroundStyle(.red)
                                }

                                Text("The following add-ons are enabled in this profile but not found in your central data folder:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Divider()

                                ForEach(Array(missingAddons.keys), id: \.self) { category in
                                    if let items = missingAddons[category], !items.isEmpty {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(category.rawValue)
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .foregroundStyle(.secondary)

                                            ForEach(items, id: \.self) { item in
                                                HStack(spacing: 6) {
                                                    Image(systemName: "xmark.circle")
                                                        .foregroundStyle(.red)
                                                    Text(item)
                                                        .font(.caption)
                                                        .fontDesign(.monospaced)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(4)
                        }
                    }

                    // Category Sections
                    categoryOverviewCard(
                        title: "Aircraft",
                        icon: "airplane",
                        category: .aircraft,
                        items: profile.aircraftFolderNames,
                        maxListHeight: 180
                    )

                    categoryOverviewCard(
                        title: "Plugins",
                        icon: "puzzlepiece.extension",
                        category: .plugins,
                        items: profile.pluginFolderNames,
                        maxListHeight: 200
                    )

                    // Scenery Packs with controlled scroll height & search
                    categoryOverviewCard(
                        title: "Scenery Packs",
                        icon: "map",
                        category: .scenery,
                        items: profile.sceneryFolderNames,
                        maxListHeight: 220
                    )

                    categoryOverviewCard(
                        title: "FlyWithLua Scripts",
                        icon: "scroll",
                        category: .luaScripts,
                        items: profile.luaScriptFolderNames,
                        maxListHeight: 180
                    )

                    // Automation & Env Vars Card
                    if !profile.scripts.isEmpty || !profile.environmentVariables.isEmpty {
                        automationOverviewCard
                    }
                }
                .padding(14)
            }
        }
    }

    private func categoryOverviewCard(
        title: String,
        icon: String,
        category: AddonCategory,
        items: [String],
        maxListHeight: CGFloat = 200
    ) -> some View {
        let missing = Set(missingAddons[category] ?? [])
        let filtered = items.filter {
            overviewSearchText.isEmpty || $0.localizedCaseInsensitiveContains(overviewSearchText)
        }

        return VStack(alignment: .leading, spacing: 0) {
            // Section Header
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.bold)

                Spacer()

                Text("\(items.count) enabled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Content List
            if items.isEmpty {
                HStack {
                    Spacer()
                    Text("No \(title.lowercased()) enabled in this profile.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 8)
                    Spacer()
                }
            } else if filtered.isEmpty {
                HStack {
                    Spacer()
                    Text("No matching items.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 8)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(filtered.enumerated()), id: \.element) { index, item in
                            HStack(spacing: 8) {
                                Image(systemName: missing.contains(item) ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(missing.contains(item) ? .red : .green)

                                Text(item)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Spacer()

                                if missing.contains(item) {
                                    Text("Not Installed")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.red.opacity(0.15))
                                        .foregroundStyle(.red)
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)

                            if index < filtered.count - 1 {
                                Divider()
                                    .padding(.leading, 30)
                            }
                        }
                    }
                }
                .frame(maxHeight: items.count > 5 ? maxListHeight : nil)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var automationOverviewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .foregroundStyle(.secondary)
                Text("Pre-launch Automation & Environment")
                    .font(.subheadline)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                if !profile.scripts.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Shell Scripts:")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        ForEach(profile.scripts) { script in
                            HStack(spacing: 6) {
                                Image(systemName: script.isEnabled ? "checkmark.circle.fill" : "circle")
                                    .font(.caption2)
                                    .foregroundStyle(script.isEnabled ? .green : .secondary)
                                Text(URL(fileURLWithPath: script.path).lastPathComponent)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Spacer()
                                Text(script.path)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                if !profile.scripts.isEmpty && !profile.environmentVariables.isEmpty {
                    Divider()
                }

                if !profile.environmentVariables.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Environment Variables:")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        ForEach(profile.environmentVariables) { envVar in
                            HStack(spacing: 4) {
                                Text(envVar.key)
                                    .font(.caption)
                                    .fontDesign(.monospaced)
                                    .fontWeight(.bold)
                                Text("=")
                                    .foregroundStyle(.secondary)
                                Text(envVar.value)
                                    .font(.caption)
                                    .fontDesign(.monospaced)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Diff Results View

    private func diffResultsView(comparing target: PluginProfile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                diffCategoryCard(
                    title: "Aircraft",
                    icon: "airplane",
                    itemsA: profile.aircraftFolderNames,
                    itemsB: target.aircraftFolderNames,
                    nameA: profile.name,
                    nameB: target.name
                )

                diffCategoryCard(
                    title: "Plugins",
                    icon: "puzzlepiece.extension",
                    itemsA: profile.pluginFolderNames,
                    itemsB: target.pluginFolderNames,
                    nameA: profile.name,
                    nameB: target.name
                )

                diffCategoryCard(
                    title: "Scenery Packs",
                    icon: "map",
                    itemsA: profile.sceneryFolderNames,
                    itemsB: target.sceneryFolderNames,
                    nameA: profile.name,
                    nameB: target.name
                )

                diffCategoryCard(
                    title: "FlyWithLua Scripts",
                    icon: "scroll",
                    itemsA: profile.luaScriptFolderNames,
                    itemsB: target.luaScriptFolderNames,
                    nameA: profile.name,
                    nameB: target.name
                )
            }
            .padding(14)
        }
    }

    private func diffCategoryCard(
        title: String,
        icon: String,
        itemsA: [String],
        itemsB: [String],
        nameA: String,
        nameB: String
    ) -> some View {
        let setA = Set(itemsA)
        let setB = Set(itemsB)

        let onlyInA = itemsA.filter { !setB.contains($0) }
        let onlyInB = itemsB.filter { !setA.contains($0) }
        let inBoth = itemsA.filter { setB.contains($0) }
        let isIdentical = onlyInA.isEmpty && onlyInB.isEmpty

        return VStack(alignment: .leading, spacing: 0) {
            // Card Header
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.bold)

                Spacer()

                if isIdentical {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Identical (\(inBoth.count))")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
                } else {
                    HStack(spacing: 6) {
                        Text("\(onlyInA.count) differences")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Card Body: Side-by-Side Dual Columns
            if isIdentical {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Text("Both profiles have the exact same \(inBoth.count) \(title.lowercased()) enabled.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 14)
                    Spacer()
                }
                .background(Color(NSColor.windowBackgroundColor).opacity(0.4))
            } else {
                HStack(alignment: .top, spacing: 0) {
                    // Left Column: Profile A Only
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text("Only in \(nameA)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.blue)
                            Text("(\(onlyInA.count))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        if onlyInA.isEmpty {
                            Text("None (all present in \(nameB))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .italic()
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 4) {
                                    ForEach(onlyInA, id: \.self) { item in
                                        HStack(spacing: 6) {
                                            Text("+")
                                                .font(.caption)
                                                .fontWeight(.bold)
                                                .foregroundStyle(.blue)
                                            Text(item)
                                                .font(.caption)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.blue.opacity(0.08))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                }
                            }
                            .frame(maxHeight: onlyInA.count > 6 ? 180 : nil)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    Divider()

                    // Right Column: Profile B Only
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text("Only in \(nameB)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.purple)
                            Text("(\(onlyInB.count))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        if onlyInB.isEmpty {
                            Text("None (all present in \(nameA))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .italic()
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 4) {
                                    ForEach(onlyInB, id: \.self) { item in
                                        HStack(spacing: 6) {
                                            Text("+")
                                                .font(.caption)
                                                .fontWeight(.bold)
                                                .foregroundStyle(.purple)
                                            Text(item)
                                                .font(.caption)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.purple.opacity(0.08))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                }
                            }
                            .frame(maxHeight: onlyInB.count > 6 ? 180 : nil)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .background(Color(NSColor.windowBackgroundColor).opacity(0.4))

                // Shared Items Footer
                if !inBoth.isEmpty {
                    Divider()
                    HStack(spacing: 6) {
                        Image(systemName: "equal.circle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(inBoth.count) shared \(title.lowercased()) enabled in both profiles")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
