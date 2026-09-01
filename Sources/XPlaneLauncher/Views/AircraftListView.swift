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

    var body: some View {
        List {
            ForEach(pluginManager.aircraft) { item in
                AircraftRow(aircraft: item, onDelete: {
                    itemToDelete = item
                })
            }

            if pluginManager.aircraft.isEmpty {
                ContentUnavailableView {
                    Label("No Aircraft Found", systemImage: "airplane")
                } description: {
                    Text("Check your Central Data Folder ('Aircraft' subfolder).")
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
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
        .onAppear {
            pluginManager.handleVolumeChange()
        }
    }
}

struct AircraftRow: View {
    @Environment(PluginManager.self) var pluginManager
    let aircraft: PluginManager.Aircraft
    var onDelete: (() -> Void)? = nil

    private var isOffline: Bool {
        pluginManager.isAircraftOffline(aircraft)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "airplane")
                .font(.title3)
                .foregroundStyle(aircraft.isEnabled && !isOffline ? .green : .secondary)
                .frame(width: 32, height: 32)
                .background(aircraft.isEnabled && !isOffline ? Color.green.opacity(0.12) : Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
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

                Text(aircraft.folderName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
