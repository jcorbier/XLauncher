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
        HStack {
            Image(systemName: script.isDirectory ? "folder.fill" : "scroll")
                .foregroundStyle(script.isEnabled ? .green : .secondary)
            
            VStack(alignment: .leading) {
                HStack(spacing: 6) {
                    Text(script.name)
                        .font(.body)
                    
                    if script.isDirectory {
                        Text("Folder")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                
                Text(script.folderName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { script.isEnabled },
                set: { _ in pluginManager.toggleLuaScript(script) }
            ))
            .toggleStyle(.switch)
        }
        .padding(.vertical, 4)
    }
}
