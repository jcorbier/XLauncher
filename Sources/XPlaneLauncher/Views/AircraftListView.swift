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
        HStack(spacing: 12) {
            Image(systemName: "airplane")
                .font(.title3)
                .foregroundStyle(aircraft.isEnabled ? .green : .secondary)
                .frame(width: 32, height: 32)
                .background(aircraft.isEnabled ? Color.green.opacity(0.12) : Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(aircraft.name)
                    .font(.body)
                    .fontWeight(.medium)
                Text(aircraft.folderName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(aircraft.isEnabled ? "Enabled" : "Disabled")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(aircraft.isEnabled ? .green : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(aircraft.isEnabled ? Color.green.opacity(0.12) : Color.secondary.opacity(0.12))
                .clipShape(Capsule())

            Toggle("", isOn: Binding(
                get: { aircraft.isEnabled },
                set: { _ in pluginManager.toggleAircraft(aircraft) }
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
