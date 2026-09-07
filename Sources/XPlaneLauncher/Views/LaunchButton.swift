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
import XLauncherPluginKit

struct LaunchButton: View {
    @Environment(PluginManager.self) var pluginManager
    @Environment(SimSessionManager.self) var simSessionManager
    @State private var showStopConfirmation = false

    var body: some View {
        if simSessionManager.isSimRunning {
            HStack(spacing: 0) {
                // 1. Live Telemetry
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .shadow(color: .green.opacity(0.8), radius: 3)
                    Image(systemName: "airplane")
                        .rotationEffect(.degrees(-45))
                        .foregroundStyle(.green)
                    Text("X-Plane 12 Active")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(simSessionManager.formattedFlightDuration)
                        .font(.subheadline)
                        .fontDesign(.monospaced)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.green.opacity(0.08))
                )

                Divider()
                    .frame(height: 20)
                    .padding(.horizontal, 6)

                // 2. Minimize Action
                CapsuleActionButton(
                    title: "Minimize",
                    systemImage: "menubar.arrow.up.rectangle"
                ) {
                    MenuBarCompanionManager.shared.hideMainWindow()
                }
                .help("Minimize to Menu Bar companion mode")

                Divider()
                    .frame(height: 20)
                    .padding(.horizontal, 6)

                // 3. Stop Simulator Action
                CapsuleActionButton(
                    title: "Stop Simulator...",
                    systemImage: "stop.circle.fill",
                    isDestructive: true
                ) {
                    showStopConfirmation = true
                }
                .help("Stop the running X-Plane simulator process")
                .popover(isPresented: $showStopConfirmation, arrowEdge: .bottom) {
                    stopConfirmationPopover
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.green.opacity(0.25), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
            )
        } else {
            Button(action: {
                pluginManager.launchXPlane()
            }) {
                HStack {
                    Image(systemName: "airplane")
                        .rotationEffect(.degrees(-45))
                    Text("Launch X-Plane")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue.gradient)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .blue.opacity(0.3), radius: 5, x: 0, y: 3)
            }
            .buttonStyle(.plain)
            .disabled(pluginManager.xPlanePath == nil)
            .opacity(pluginManager.xPlanePath == nil ? 0.6 : 1.0)
        }
    }

    private var stopConfirmationPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("Stop X-Plane 12?")
                    .font(.headline)
            }

            Text("Are you sure you want to stop X-Plane?")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Cancel") {
                    showStopConfirmation = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Stop Simulator", role: .destructive) {
                    showStopConfirmation = false
                    simSessionManager.forceQuitSimulator()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(14)
        .frame(width: 280)
    }
}

// MARK: - Capsule Action Button
private struct CapsuleActionButton: View {
    let title: String
    let systemImage: String
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .foregroundStyle(isDestructive ? Color.red : Color.secondary)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(isDestructive ? Color.red : Color.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? (isDestructive ? Color.red.opacity(0.12) : Color.primary.opacity(0.08)) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
