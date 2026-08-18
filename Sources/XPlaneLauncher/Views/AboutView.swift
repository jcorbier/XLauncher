//
//  MIT License
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

struct AboutView: View {
    @State private var copiedLicense: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                Label("About", systemImage: "info.circle")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Hero Header
                    VStack(spacing: 12) {
                        if let iconImage = NSApp.applicationIconImage {
                            Image(nsImage: iconImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 72, height: 72)
                                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                        } else {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 72, height: 72)
                                Image(systemName: "airplane.departure")
                                    .font(.system(size: 32, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                        }
                        
                        VStack(spacing: 4) {
                            Text(AppInfo.appName)
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text(AppInfo.displayVersion)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                            
                            Text("A native macOS add-on manager and profile launcher for X-Plane 12.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.top, 2)
                        }
                    }
                    .padding(.top, 12)
                    
                    // Links & Resources
                    GroupBox("Links & Resources") {
                        VStack(spacing: 8) {
                            LinkRow(
                                icon: "chevron.left.forwardslash.chevron.right",
                                title: "GitHub Repository",
                                subtitle: "Source code, contributions, and discussions",
                                url: AppInfo.githubURL
                            )
                            
                            Divider()
                            
                            LinkRow(
                                icon: "tag",
                                title: "Releases & Changelog",
                                subtitle: "Download binary packages and view version release notes",
                                url: AppInfo.releasesURL
                            )
                            
                            Divider()
                            
                            LinkRow(
                                icon: "ladybug",
                                title: "Issue Tracker",
                                subtitle: "Report bugs, issues, or request new features",
                                url: AppInfo.issuesURL
                            )
                        }
                        .padding(8)
                    }
                    
                    // Author & Copyright
                    GroupBox("Author & Credits") {
                        VStack(spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Created by")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(AppInfo.author)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    NSWorkspace.shared.open(AppInfo.authorURL)
                                }) {
                                    HStack(spacing: 4) {
                                        Text("@jcorbier")
                                            .font(.caption)
                                        Image(systemName: "arrow.up.right")
                                            .font(.caption2)
                                    }
                                }
                                .buttonStyle(.link)
                            }
                            
                            Divider()
                            
                            HStack {
                                Text(AppInfo.copyright)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Special Thanks & Integrations")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                                
                                Text("Built for X-Plane 12 by Laminar Research. Integrates with SkunkCrafts Updater, X-Updater, and the X-CSL multiplayer aircraft library.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(8)
                    }
                    
                    // License
                    GroupBox("License") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label(AppInfo.license, systemImage: "doc.text")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                
                                Spacer()
                                
                                Button(action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(AppInfo.licenseText, forType: .string)
                                    copiedLicense = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        copiedLicense = false
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: copiedLicense ? "checkmark" : "doc.on.doc")
                                        Text(copiedLicense ? "Copied" : "Copy License")
                                    }
                                    .font(.caption)
                                }
                                .controlSize(.small)
                            }
                            
                            ScrollView(.vertical) {
                                Text(AppInfo.licenseText)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                            }
                            .frame(maxHeight: 140)
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                            )
                        }
                        .padding(8)
                    }
                }
                .padding(16)
                .frame(maxWidth: 680)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LinkRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let url: URL
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button(action: {
                NSWorkspace.shared.open(url)
            }) {
                HStack(spacing: 4) {
                    Text("Open")
                        .font(.caption)
                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 2)
    }
}
