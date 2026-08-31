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
import AppKit

struct AddonReleaseNotesSheet: View {
    @Environment(UpdateManager.self) var updateManager
    @Environment(\.dismiss) private var dismiss

    let addon: UpdateManager.UpdatableAddon

    @State private var releaseNotes: String? = nil
    @State private var isLoading: Bool = true
    @State private var isCopied: Bool = false

    private var categoryColor: Color {
        switch addon.addonCategory {
        case .aircraft: return .blue
        case .plugin: return .green
        case .scenery: return .orange
        case .luaScript: return .purple
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                Image(systemName: addon.updaterType == .skunkcrafts ? "gearshape.2.fill" : "arrow.down.circle.fill")
                    .font(.title2)
                    .foregroundStyle(categoryColor)
                    .frame(width: 40, height: 40)
                    .background(categoryColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(addon.name)
                            .font(.title3)
                            .fontWeight(.bold)

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
                    }

                    HStack(spacing: 8) {
                        if let cur = addon.currentVersion, let latest = addon.latestVersion, cur != latest {
                            Text("Version \(cur)  →  \(latest)")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                        } else if let ver = addon.latestVersion ?? addon.currentVersion {
                            Text("Version \(ver)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text("•  \(addon.folderName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Main Content Area
            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.regular)
                        Text("Fetching release notes...")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let notes = releaseNotes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ScrollView {
                        MarkdownView(markdown: notes)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                    }
                    .background(Color(NSColor.textBackgroundColor))
                } else {
                    ContentUnavailableView {
                        Label("No Release Notes Available", systemImage: "doc.text")
                    } description: {
                        Text("No changelog or release notes file was found in the remote update manifest or the local add-on folder.")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 40)
                    .background(Color(NSColor.textBackgroundColor))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Footer Bar
            HStack(spacing: 12) {
                Button(action: {
                    NSWorkspace.shared.activateFileViewerSelecting([addon.folderURL])
                }) {
                    Label("Show in Finder", systemImage: "folder")
                }
                .controlSize(.small)

                if let notes = releaseNotes, !notes.isEmpty {
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(notes, forType: .string)
                        isCopied = true
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            isCopied = false
                        }
                    }) {
                        Label(isCopied ? "Copied!" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                    }
                    .controlSize(.small)
                }

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .controlSize(.small)

                if addon.isUpdateAvailable {
                    let isRepair = (addon.statusMessage.lowercased().contains("repair") || (addon.currentVersion != nil && addon.latestVersion != nil && addon.currentVersion == addon.latestVersion))
                    Button(action: {
                        dismiss()
                        updateManager.updateAddon(addon)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            Text(isRepair ? "Verify & Repair Files" : "Update Add-on")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isRepair ? .orange : .accentColor)
                    .controlSize(.regular)
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(minWidth: 560, idealWidth: 640, minHeight: 440, idealHeight: 520)
        .task {
            isLoading = true
            releaseNotes = await updateManager.fetchReleaseNotes(for: addon)
            isLoading = false
        }
    }
}
