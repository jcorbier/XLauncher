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

struct AppReleaseNotesSheet: View {
    @Environment(AppUpdateManager.self) var appUpdateManager
    @Environment(\.dismiss) private var dismiss

    let releases: [AppRelease]

    init(releases: [AppRelease]) {
        self.releases = releases
    }

    init(release: AppRelease) {
        self.releases = [release]
    }

    private var latestRelease: AppRelease? {
        releases.first
    }

    private func formatReleaseDate(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main Window Header
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title)
                    .foregroundStyle(.orange)
                    .frame(width: 42, height: 42)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    if releases.count > 1 {
                        Text("What's New in X-Plane Launcher")
                            .font(.title3)
                            .fontWeight(.bold)

                        Text("\(releases.count) updates available since your current version (\(AppInfo.displayVersion))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let release = latestRelease {
                        HStack(spacing: 8) {
                            Text(release.displayTitle)
                                .font(.title3)
                                .fontWeight(.bold)

                            if release.isPrerelease {
                                Text("Pre-release")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }

                        HStack(spacing: 8) {
                            Text("Tag: \(release.tagName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            let dateStr = formatReleaseDate(release.publishedAt)
                            if !dateStr.isEmpty {
                                Text("•  Published \(dateStr)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("Release Notes")
                            .font(.title3)
                            .fontWeight(.bold)
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

            // Scrollable Releases List
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if releases.isEmpty {
                        ContentUnavailableView("No Release Notes Available", systemImage: "doc.text")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.vertical, 40)
                    } else {
                        ForEach(releases.indices, id: \.self) { idx in
                            let item = releases[idx]
                            VStack(alignment: .leading, spacing: 14) {
                                // Multi-release item header
                                if releases.count > 1 {
                                    HStack(alignment: .center, spacing: 10) {
                                        Text(item.tagName)
                                            .font(.headline)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.primary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Color.accentColor.opacity(0.12))
                                            .clipShape(Capsule())

                                        if let name = item.name, !name.isEmpty && name != item.tagName {
                                            Text(name)
                                                .font(.headline)
                                                .fontWeight(.semibold)
                                        }

                                        if item.isPrerelease {
                                            Text("Pre-release")
                                                .font(.caption2)
                                                .fontWeight(.semibold)
                                                .foregroundStyle(.orange)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.orange.opacity(0.12))
                                                .clipShape(Capsule())
                                        }

                                        Spacer()

                                        let dateStr = formatReleaseDate(item.publishedAt)
                                        if !dateStr.isEmpty {
                                            Text(dateStr)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.bottom, 4)
                                }

                                // Formatted Markdown Changelog Body
                                if let notes = item.body, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    MarkdownView(markdown: notes)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                } else {
                                    Text("No release notes provided for this version.")
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .italic()
                                        .padding(.vertical, 4)
                                }
                            }

                            if idx < releases.count - 1 {
                                Divider()
                                    .padding(.top, 8)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(NSColor.textBackgroundColor))

            Divider()

            // Footer Actions
            HStack(spacing: 12) {
                Button(action: {
                    appUpdateManager.openReleasePage()
                }) {
                    HStack(spacing: 4) {
                        Text("View on GitHub")
                        Image(systemName: "arrow.up.right")
                            .font(.caption2)
                    }
                }
                .buttonStyle(.link)

                Spacer()

                if let dmg = latestRelease?.dmgAsset {
                    Button(action: {
                        appUpdateManager.downloadLatestDMG()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Download Installer (\(dmg.formattedSize))")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                } else {
                    Button(action: {
                        appUpdateManager.openReleasePage()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Download Release (.dmg)")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(minWidth: 560, idealWidth: 640, minHeight: 440, idealHeight: 520)
    }
}
