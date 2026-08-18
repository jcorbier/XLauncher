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

struct PluginListView: View {
    @Environment(PluginManager.self) var pluginManager
    
    // Sort logic handled in manager, or here. Manager is cleaner.
    
    var body: some View {
        List {
            ForEach(pluginManager.plugins) { plugin in
                PluginRow(plugin: plugin)
            }
            
            if pluginManager.plugins.isEmpty {
                ContentUnavailableView {
                    Label("No Plugins Found", systemImage: "puzzlepiece.extension")
                } description: {
                    Text("Check your Central Data Folder ('Plugins' subfolder).")
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }
}

struct PluginRow: View {
    @Environment(PluginManager.self) var pluginManager
    let plugin: PluginManager.Plugin
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.title3)
                .foregroundStyle(plugin.isEnabled ? .green : .secondary)
                .frame(width: 32, height: 32)
                .background(plugin.isEnabled ? Color.green.opacity(0.12) : Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.name)
                    .font(.body)
                    .fontWeight(.medium)
                Text(plugin.folderName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(plugin.isEnabled ? "Enabled" : "Disabled")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(plugin.isEnabled ? .green : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(plugin.isEnabled ? Color.green.opacity(0.12) : Color.secondary.opacity(0.12))
                .clipShape(Capsule())
            
            Toggle("", isOn: Binding(
                get: { plugin.isEnabled },
                set: { _ in pluginManager.togglePlugin(plugin) }
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
