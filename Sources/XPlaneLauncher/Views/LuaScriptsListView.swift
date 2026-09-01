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

struct LuaScriptsListView: View {
    @Environment(PluginManager.self) var pluginManager
    @State private var itemToDelete: PluginManager.LuaScript? = nil

    var body: some View {
        List {
            ForEach(pluginManager.luaScripts) { item in
                LuaScriptRow(script: item, onDelete: {
                    itemToDelete = item
                })
            }

            if pluginManager.luaScripts.isEmpty {
                ContentUnavailableView {
                    Label("No FlyWithLua Scripts Found", systemImage: "scroll")
                } description: {
                    Text("Check your Central Data Folder ('LuaScripts' subfolder).")
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .alert(
            "Delete FlyWithLua Script",
            isPresented: Binding(
                get: { itemToDelete != nil },
                set: { if !$0 { itemToDelete = nil } }
            ),
            presenting: itemToDelete
        ) { item in
            Button("Delete", role: .destructive) {
                pluginManager.deleteLuaScript(item)
            }
            Button("Cancel", role: .cancel) { }
        } message: { item in
            Text("Are you sure you want to delete '\(item.name)'?\n\nThis will permanently delete the files from your Central Data Folder ('LuaScripts/\(item.folderName)'), unlink it from X-Plane, and remove it from all profiles.\n\nThis action cannot be undone.")
        }
        .onAppear {
            pluginManager.handleVolumeChange()
        }
    }
}

struct LuaScriptRow: View {
    @Environment(PluginManager.self) var pluginManager
    let script: PluginManager.LuaScript
    var onDelete: (() -> Void)? = nil

    private var isOffline: Bool {
        pluginManager.isLuaScriptOffline(script)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: script.isDirectory ? "folder.fill" : "scroll")
                .font(.title3)
                .foregroundStyle(script.isEnabled && !isOffline ? .green : .secondary)
                .frame(width: 32, height: 32)
                .background(script.isEnabled && !isOffline ? Color.green.opacity(0.12) : Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(script.name)
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

                    if script.isDirectory {
                        Text("Folder")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    if let poolName = script.storagePoolName, pluginManager.storagePools.count > 1 {
                        Text(poolName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color(NSColor.windowBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                Text(script.folderName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if pluginManager.isLuaScriptModified(script) {
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
                Text(script.isEnabled ? "Enabled" : "Disabled")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(script.isEnabled ? .green : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(script.isEnabled ? Color.green.opacity(0.12) : Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }

            Toggle("", isOn: Binding(
                get: { script.isEnabled && !isOffline },
                set: { _ in pluginManager.toggleLuaScript(script) }
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
