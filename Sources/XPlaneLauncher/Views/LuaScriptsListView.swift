//
//  LuaScriptsListView.swift
//  XPlaneLauncher
//

import SwiftUI

struct LuaScriptsListView: View {
    @Environment(PluginManager.self) var pluginManager
    
    var body: some View {
        List {
            ForEach(pluginManager.luaScripts) { item in
                LuaScriptRow(script: item)
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
    }
}

struct LuaScriptRow: View {
    @Environment(PluginManager.self) var pluginManager
    let script: PluginManager.LuaScript
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: script.isDirectory ? "folder.fill" : "scroll")
                .font(.title3)
                .foregroundStyle(script.isEnabled ? .green : .secondary)
                .frame(width: 32, height: 32)
                .background(script.isEnabled ? Color.green.opacity(0.12) : Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(script.name)
                        .font(.body)
                        .fontWeight(.medium)
                    
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
                }
                
                Text(script.folderName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(script.isEnabled ? "Enabled" : "Disabled")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(script.isEnabled ? .green : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(script.isEnabled ? Color.green.opacity(0.12) : Color.secondary.opacity(0.12))
                .clipShape(Capsule())
            
            Toggle("", isOn: Binding(
                get: { script.isEnabled },
                set: { _ in pluginManager.toggleLuaScript(script) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
    }
}
