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

struct UpdatesView: View {
    @Environment(UpdateManager.self) var updateManager
    @State private var selectedFilter: AddonCategoryFilter = .all
    @State private var showDebugConsole: Bool = false
    @State private var selectedAddonForReleaseNotes: UpdateManager.UpdatableAddon? = nil
    @State private var expandedPackIDs: Set<String> = []

    enum AddonCategoryFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case aircraft = "Aircraft"
        case plugin = "Plugins"
        case scenery = "Scenery"
        case luaScript = "Lua Scripts"

        var id: String { rawValue }
    }

    var filteredAddons: [UpdateManager.UpdatableAddon] {
        switch selectedFilter {
        case .all:
            return updateManager.updatableAddons
        case .aircraft:
            return updateManager.updatableAddons.filter { $0.addonCategory == .aircraft }
        case .plugin:
            return updateManager.updatableAddons.filter { $0.addonCategory == .plugin }
        case .scenery:
            return updateManager.updatableAddons.filter { $0.addonCategory == .scenery }
        case .luaScript:
            return updateManager.updatableAddons.filter { $0.addonCategory == .luaScript }
        }
    }

    var groupedItems: [UpdateManager.UpdatableItem] {
        UpdateManager.groupAddons(filteredAddons)
    }

    var hasAvailableUpdates: Bool {
        updateManager.updatableAddons.contains { $0.isUpdateAvailable }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                Label("Add-ons", systemImage: "arrow.triangle.2.circlepath")
                    .font(.title3)
                    .fontWeight(.bold)

                Spacer()

                Picker("Filter", selection: $selectedFilter) {
                    ForEach(AddonCategoryFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .frame(width: 140)
                .labelsHidden()

                Button(action: {
                    updateManager.scanAndCheckAllAddonUpdates()
                }) {
                    if updateManager.isCheckingUpdates {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Checking...")
                        }
                    } else {
                        Label("Check for Updates", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(updateManager.isProcessing)

                Button(action: {
                    for addon in updateManager.updatableAddons where addon.isUpdateAvailable {
                        updateManager.updateAddon(addon)
                    }
                }) {
                    Label("Update All", systemImage: "square.and.arrow.down")
                }
                .disabled(!hasAvailableUpdates || updateManager.isProcessing)

                Button(action: {
                    showDebugConsole.toggle()
                }) {
                    Label("Console", systemImage: showDebugConsole ? "terminal.fill" : "terminal")
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // List / Empty State
            if groupedItems.isEmpty {
                ContentUnavailableView {
                    Label("No Updatable Addons Found", systemImage: "arrow.triangle.2.circlepath")
                } description: {
                    Text("Addons with SkunkCrafts (skunkcrafts_updater.cfg) or X-Updater (x-updater.json) configuration files in your Central Data Folder will automatically appear here.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(groupedItems) { item in
                        switch item {
                        case .standalone(let addon):
                            UpdatableAddonRow(addon: addon, onShowReleaseNotes: { addon in
                                selectedAddonForReleaseNotes = addon
                            })
                        case .pack(let pack):
                            UpdatablePackRow(
                                pack: pack,
                                isExpanded: Binding(
                                    get: { expandedPackIDs.contains(pack.id) },
                                    set: { expanded in
                                        if expanded {
                                            expandedPackIDs.insert(pack.id)
                                        } else {
                                            expandedPackIDs.remove(pack.id)
                                        }
                                    }
                                ),
                                onShowReleaseNotes: { addon in
                                    selectedAddonForReleaseNotes = addon
                                }
                            )
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }

            if showDebugConsole {
                Divider()
                ConsoleView(title: "Updates Console", logger: updateManager.logger, initialCategory: .updates)
                    .frame(height: 180)
            }
        }
        .sheet(item: $selectedAddonForReleaseNotes) { addon in
            AddonReleaseNotesSheet(addon: addon)
        }
    }
}

struct UpdatableAddonRow: View {
    @Environment(UpdateManager.self) var updateManager
    let addon: UpdateManager.UpdatableAddon
    var onShowReleaseNotes: ((UpdateManager.UpdatableAddon) -> Void)? = nil

    var categoryColor: Color {
        switch addon.addonCategory {
        case .aircraft: return .blue
        case .plugin: return .green
        case .scenery: return .orange
        case .luaScript: return .purple
        }
    }

    var statusColor: Color {
        if addon.isUpdateAvailable {
            return .orange
        }
        let msg = addon.statusMessage.lowercased()
        if msg == "unknown" || msg == "idle" {
            return .secondary
        }
        if msg.contains("fail") || msg.contains("error") {
            return .red
        }
        return .green
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: addon.updaterType == .skunkcrafts ? "gearshape.2.fill" : "arrow.down.circle.fill")
                .font(.title3)
                .foregroundStyle(categoryColor)
                .frame(width: 36, height: 36)
                .background(categoryColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(addon.name)
                        .font(.body)
                        .fontWeight(.medium)

                    Text(addon.addonCategory.rawValue)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(categoryColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(categoryColor.opacity(0.12))
                        .clipShape(Capsule())

                    Text(addon.updaterType.rawValue)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())

                    let channel = addon.activeChannel.lowercased()
                    let isCustomMain = (channel == "stable" && addon.mainChannelName != nil && !addon.mainChannelName!.isEmpty)
                    if (channel != "stable" && channel != "release" && !channel.isEmpty) || isCustomMain {
                        let isBeta = (channel == "beta")
                        let badgeText = isCustomMain ? addon.mainChannelName! : addon.activeChannel.uppercased()
                        Text(badgeText)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(isBeta ? .purple : .blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((isBeta ? Color.purple : Color.blue).opacity(0.15))
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 8) {
                    Text(addon.folderName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let ver = addon.currentVersion {
                        let channelSuffix: String = {
                            let ch = addon.activeChannel.lowercased()
                            if ch != "stable" && ch != "release" && !ch.isEmpty {
                                return " (\(addon.activeChannel.capitalized) Channel)"
                            } else if let mainName = addon.mainChannelName, !mainName.isEmpty {
                                return " (\(mainName) Channel)"
                            }
                            return ""
                        }()
                        Text("•  Version \(ver)\(channelSuffix)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if addon.isChecking || addon.isUpdating {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(addon.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 8) {
                    Text(addon.statusMessage)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor.opacity(0.12))
                        .clipShape(Capsule())

                    if addon.isUpdateAvailable {
                        let isRepair = (addon.statusMessage.lowercased().contains("repair") || (addon.currentVersion != nil && addon.latestVersion != nil && addon.currentVersion == addon.latestVersion))
                        Menu {
                            Button {
                                onShowReleaseNotes?(addon)
                            } label: {
                                Label("Show Changes...", systemImage: "doc.text")
                            }
                            Divider()
                            Button("Verify & Repair Files") {
                                updateManager.updateAddon(addon)
                            }
                            channelMenuSection
                        } label: {
                            Text(isRepair ? "Repair" : "Update")
                        } primaryAction: {
                            updateManager.updateAddon(addon)
                        }
                        .menuStyle(.borderedButton)
                        .buttonStyle(.borderedProminent)
                        .tint(isRepair ? .orange : .accentColor)
                        .controlSize(.small)
                    } else {
                        Menu {
                            Button("Check for Updates") {
                                updateManager.checkForUpdates(for: addon)
                            }
                            Button {
                                onShowReleaseNotes?(addon)
                            } label: {
                                Label("Show Changes...", systemImage: "doc.text")
                            }
                            Button("Verify & Repair Files") {
                                updateManager.updateAddon(addon)
                            }
                            channelMenuSection
                        } label: {
                            Text("Check")
                        } primaryAction: {
                            updateManager.checkForUpdates(for: addon)
                        }
                        .menuStyle(.borderedButton)
                        .controlSize(.small)
                    }
                }
            }
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
                onShowReleaseNotes?(addon)
            } label: {
                Label("Show Changes...", systemImage: "doc.text")
            }
            Divider()
            Button("Check for Updates") {
                updateManager.checkForUpdates(for: addon)
            }
            Button("Verify & Repair Files") {
                updateManager.updateAddon(addon)
            }
            channelMenuSection
            Divider()
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([addon.folderURL])
            }
        }
    }

    private func channelDisplayName(_ ch: String) -> String {
        if ch.lowercased() == "stable", let mainName = addon.mainChannelName, !mainName.isEmpty {
            return mainName
        }
        return ch.capitalized
    }

    @ViewBuilder
    private var channelMenuSection: some View {
        if addon.availableChannels.count > 1 {
            Divider()
            Menu {
                ForEach(addon.availableChannels, id: \.self) { ch in
                    Button {
                        updateManager.setChannel(ch, for: addon)
                    } label: {
                        let name = channelDisplayName(ch)
                        if ch.lowercased() == addon.activeChannel.lowercased() {
                            Label(name, systemImage: "checkmark")
                        } else {
                            Text(name)
                        }
                    }
                }
            } label: {
                Label("Channel: \(channelDisplayName(addon.activeChannel))", systemImage: "arrow.triangle.branch")
            }
            .disabled(addon.isUpdating)
        }
    }
}

struct UpdatablePackRow: View {
    @Environment(UpdateManager.self) var updateManager
    let pack: UpdateManager.UpdatablePack
    var isExpanded: Binding<Bool>
    var onShowReleaseNotes: ((UpdateManager.UpdatableAddon) -> Void)? = nil

    var categoryColor: Color {
        switch pack.category {
        case .aircraft: return .blue
        case .plugin: return .green
        case .scenery: return .orange
        case .luaScript: return .purple
        }
    }

    var statusColor: Color {
        if pack.isUpdateAvailable {
            return .orange
        }
        let msg = pack.statusMessage.lowercased()
        if msg == "unknown" || msg == "idle" {
            return .secondary
        }
        if msg.contains("fail") || msg.contains("error") {
            return .red
        }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.wrappedValue.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)

                Image(systemName: "square.stack.3d.up.fill")
                    .font(.title3)
                    .foregroundStyle(categoryColor)
                    .frame(width: 36, height: 36)
                    .background(categoryColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(pack.displayName)
                            .font(.body)
                            .fontWeight(.medium)

                        Text(pack.category.rawValue)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(categoryColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(categoryColor.opacity(0.12))
                            .clipShape(Capsule())

                        Text(pack.updaterType.rawValue)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())

                        Text(pack.members.count == 1 ? "1 folder" : "\(pack.members.count) folders")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())

                        let channel = pack.activeChannel.lowercased()
                        let isCustomMain = (channel == "stable" && pack.mainChannelName != nil && !pack.mainChannelName!.isEmpty)
                        if (channel != "stable" && channel != "release" && channel != "mixed" && !channel.isEmpty) || isCustomMain {
                            let isBeta = (channel == "beta")
                            let badgeText = isCustomMain ? pack.mainChannelName! : pack.activeChannel.uppercased()
                            Text(badgeText)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(isBeta ? .purple : .blue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background((isBeta ? Color.purple : Color.blue).opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }

                    HStack(spacing: 8) {
                        Text("Pack: \(pack.packId)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let ver = pack.displayVersion {
                            let channelSuffix: String = {
                                let ch = pack.activeChannel.lowercased()
                                if ch != "stable" && ch != "release" && ch != "mixed" && !ch.isEmpty {
                                    return " (\(pack.activeChannel.capitalized) Channel)"
                                } else if let mainName = pack.mainChannelName, !mainName.isEmpty {
                                    return " (\(mainName) Channel)"
                                }
                                return ""
                            }()
                            Text("•  Version \(ver)\(channelSuffix)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.wrappedValue.toggle()
                    }
                }

                Spacer()

                if pack.isChecking || pack.isUpdating {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(pack.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 8) {
                        Text(pack.statusMessage)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(statusColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(statusColor.opacity(0.12))
                            .clipShape(Capsule())

                        if pack.isUpdateAvailable {
                            let isRepair = !pack.statusMessage.lowercased().contains("update available") && pack.statusMessage.lowercased().contains("repair")
                            Menu {
                                Button {
                                    if let target = pack.members.first(where: { $0.isUpdateAvailable }) ?? pack.members.first {
                                        onShowReleaseNotes?(target)
                                    }
                                } label: {
                                    Label("Show Changes...", systemImage: "doc.text")
                                }
                                Divider()
                                Button("Update All (\(pack.members.count) Folders)") {
                                    updateManager.updatePack(pack)
                                }
                                Button("Verify & Repair All Folders") {
                                    updateManager.repairPack(pack)
                                }
                                packChannelMenuSection
                            } label: {
                                Text(isRepair ? "Repair" : "Update")
                            } primaryAction: {
                                updateManager.updatePack(pack)
                            }
                            .menuStyle(.borderedButton)
                            .buttonStyle(.borderedProminent)
                            .tint(isRepair ? .orange : .accentColor)
                            .controlSize(.small)
                        } else {
                            Menu {
                                Button("Check for Updates") {
                                    updateManager.checkForUpdates(forPack: pack)
                                }
                                Button {
                                    if let target = pack.members.first {
                                        onShowReleaseNotes?(target)
                                    }
                                } label: {
                                    Label("Show Changes...", systemImage: "doc.text")
                                }
                                Button("Verify & Repair All Folders") {
                                    updateManager.repairPack(pack)
                                }
                                packChannelMenuSection
                            } label: {
                                Text("Check")
                            } primaryAction: {
                                updateManager.checkForUpdates(forPack: pack)
                            }
                            .menuStyle(.borderedButton)
                            .controlSize(.small)
                        }
                    }
                }
            }

            if isExpanded.wrappedValue {
                Divider()
                    .padding(.vertical, 8)

                VStack(spacing: 6) {
                    ForEach(pack.members) { member in
                        UpdatablePackMemberRow(
                            member: member,
                            categoryColor: categoryColor,
                            onShowReleaseNotes: onShowReleaseNotes
                        )
                        if member.id != pack.members.last?.id {
                            Divider()
                                .opacity(0.3)
                                .padding(.leading, 34)
                        }
                    }
                }
                .padding(.leading, 28)
                .padding(.bottom, 4)
            }
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
                if let target = pack.members.first(where: { $0.isUpdateAvailable }) ?? pack.members.first {
                    onShowReleaseNotes?(target)
                }
            } label: {
                Label("Show Changes...", systemImage: "doc.text")
            }
            Divider()
            Button("Check All Folders") {
                updateManager.checkForUpdates(forPack: pack)
            }
            Button("Update All Folders") {
                updateManager.updatePack(pack)
            }
            Button("Verify & Repair All Folders") {
                updateManager.repairPack(pack)
            }
            packChannelMenuSection
            Divider()
            Button("Show in Finder") {
                let parentFolder = pack.members.first?.folderURL.deletingLastPathComponent()
                if let p = parentFolder, FileManager.default.fileExists(atPath: p.path) {
                    NSWorkspace.shared.activateFileViewerSelecting([p])
                } else if let firstMember = pack.members.first {
                    NSWorkspace.shared.activateFileViewerSelecting([firstMember.folderURL])
                }
            }
        }
    }

    private func channelDisplayName(_ ch: String) -> String {
        if ch.lowercased() == "stable", let mainName = pack.mainChannelName, !mainName.isEmpty {
            return mainName
        }
        return ch.capitalized
    }

    @ViewBuilder
    private var packChannelMenuSection: some View {
        if pack.availableChannels.count > 1 {
            Divider()
            Menu {
                ForEach(pack.availableChannels, id: \.self) { ch in
                    Button {
                        updateManager.setChannel(ch, forPack: pack)
                    } label: {
                        let name = channelDisplayName(ch)
                        if ch.lowercased() == pack.activeChannel.lowercased() {
                            Label(name, systemImage: "checkmark")
                        } else {
                            Text(name)
                        }
                    }
                }
            } label: {
                let current = pack.activeChannel.isEmpty || pack.activeChannel == "mixed" ? "Mixed" : channelDisplayName(pack.activeChannel)
                Label("Channel: \(current)", systemImage: "arrow.triangle.branch")
            }
            .disabled(pack.isUpdating)
        }
    }
}

struct UpdatablePackMemberRow: View {
    @Environment(UpdateManager.self) var updateManager
    let member: UpdateManager.UpdatableAddon
    let categoryColor: Color
    var onShowReleaseNotes: ((UpdateManager.UpdatableAddon) -> Void)? = nil

    var statusColor: Color {
        if member.isUpdateAvailable {
            return .orange
        }
        let msg = member.statusMessage.lowercased()
        if msg == "unknown" || msg == "idle" {
            return .secondary
        }
        if msg.contains("fail") || msg.contains("error") {
            return .red
        }
        return .green
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .font(.callout)
                .foregroundStyle(categoryColor.opacity(0.85))
                .frame(width: 24, height: 24)
                .background(categoryColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.name)
                        .font(.callout)
                        .fontWeight(.medium)

                    if let mId = member.memberId, mId != member.name {
                        Text(mId)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 6) {
                    Text(member.folderName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if let ver = member.currentVersion {
                        Text("•  v\(ver)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if member.isChecking || member.isUpdating {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(member.statusMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 6) {
                    Text(member.statusMessage)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor.opacity(0.12))
                        .clipShape(Capsule())

                    if member.isUpdateAvailable {
                        let isRepair = (member.statusMessage.lowercased().contains("repair") || (member.currentVersion != nil && member.latestVersion != nil && member.currentVersion == member.latestVersion))
                        Menu {
                            Button {
                                onShowReleaseNotes?(member)
                            } label: {
                                Label("Show Changes...", systemImage: "doc.text")
                            }
                            Divider()
                            Button("Verify & Repair Files") {
                                updateManager.updateAddon(member)
                            }
                        } label: {
                            Text(isRepair ? "Repair" : "Update")
                        } primaryAction: {
                            updateManager.updateAddon(member)
                        }
                        .menuStyle(.borderedButton)
                        .buttonStyle(.borderedProminent)
                        .tint(isRepair ? .orange : .accentColor)
                        .controlSize(.mini)
                    } else {
                        Menu {
                            Button("Check for Updates") {
                                updateManager.checkForUpdates(for: member)
                            }
                            Button {
                                onShowReleaseNotes?(member)
                            } label: {
                                Label("Show Changes...", systemImage: "doc.text")
                            }
                            Button("Verify & Repair Files") {
                                updateManager.updateAddon(member)
                            }
                        } label: {
                            Text("Check")
                        } primaryAction: {
                            updateManager.checkForUpdates(for: member)
                        }
                        .menuStyle(.borderedButton)
                        .controlSize(.mini)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                onShowReleaseNotes?(member)
            } label: {
                Label("Show Changes...", systemImage: "doc.text")
            }
            Divider()
            Button("Check for Updates") {
                updateManager.checkForUpdates(for: member)
            }
            Button("Verify & Repair Files") {
                updateManager.updateAddon(member)
            }
            Divider()
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([member.folderURL])
            }
        }
    }
}

