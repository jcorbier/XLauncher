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

struct ConsoleView: View {
    let title: String
    let logger: ConsoleLogger
    
    @State private var hasCopied: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header Bar
            HStack(spacing: 8) {
                Label("\(title) (\(logger.entries.count) entries)", systemImage: "terminal")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button(action: copyAllLogs) {
                    HStack(spacing: 4) {
                        Image(systemName: hasCopied ? "checkmark" : "doc.on.doc")
                        Text(hasCopied ? "Copied" : "Copy")
                    }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(hasCopied ? Color.green : Color.secondary)
                .disabled(logger.entries.isEmpty)
                
                Text("•")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                
                Button("Clear") {
                    logger.clear()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .disabled(logger.entries.isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            
            // Console Output Scroll Area
            ScrollViewReader { proxy in
                ScrollView {
                    if logger.entries.isEmpty {
                        Text("Console is empty.")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Color.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(logger.entries.enumerated()), id: \.offset) { index, log in
                                Text(log)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(Color.green)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }
                        .padding(8)
                    }
                }
                .textSelection(.enabled)
                .background(Color.black.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .onAppear {
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: logger.entries.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
            }
        }
        .frame(height: 180)
        .background(Color(NSColor.controlBackgroundColor))
        .contextMenu {
            Button("Copy All Logs") {
                copyAllLogs()
            }
            .disabled(logger.entries.isEmpty)
            
            Divider()
            
            Button("Clear Console") {
                logger.clear()
            }
            .disabled(logger.entries.isEmpty)
        }
    }
    
    private func copyAllLogs() {
        guard !logger.entries.isEmpty else { return }
        let text = logger.entries.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        
        withAnimation {
            hasCopied = true
        }
        
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                withAnimation {
                    hasCopied = false
                }
            }
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let lastIndex = logger.entries.indices.last else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(lastIndex, anchor: .bottom)
        }
    }
}
