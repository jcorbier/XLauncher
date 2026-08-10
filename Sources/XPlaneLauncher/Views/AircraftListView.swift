//
//  AircraftListView.swift
//  XPlaneLauncher
//

import SwiftUI

struct AircraftListView: View {
    @Environment(PluginManager.self) var pluginManager
    
    var body: some View {
        List {
            ForEach(pluginManager.aircraft) { item in
                AircraftRow(aircraft: item)
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
    }
}

struct AircraftRow: View {
    @Environment(PluginManager.self) var pluginManager
    let aircraft: PluginManager.Aircraft
    
    var body: some View {
        HStack {
            Image(systemName: "airplane")
                .foregroundStyle(aircraft.isEnabled ? .green : .secondary)
            
            VStack(alignment: .leading) {
                Text(aircraft.name)
                    .font(.body)
                Text(aircraft.folderName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { aircraft.isEnabled },
                set: { _ in pluginManager.toggleAircraft(aircraft) }
            ))
            .toggleStyle(.switch)
        }
        .padding(.vertical, 4)
    }
}
