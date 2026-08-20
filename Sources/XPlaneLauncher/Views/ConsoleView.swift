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

    @State private var selectedCategory: LogCategory?
    @State private var searchText: String = ""
    @State private var hasCopied: Bool = false

    init(title: String = "Live Console", logger: ConsoleLogger = .shared, initialCategory: LogCategory? = nil) {
        self.title = title
        self.logger = logger
        self._selectedCategory = State(initialValue: initialCategory)
    }

    private var filteredEntries: [LogEntry] {
        logger.filteredEntries(category: selectedCategory, searchText: searchText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header Bar
            HStack(spacing: 8) {
                Label("\(title) (\(filteredEntries.count))", systemImage: "terminal")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                Spacer()

                // Subsystem Category Filter Menu
                Menu {
                    Button {
                        selectedCategory = nil
                    } label: {
                        HStack {
                            Text("All Subsystems")
                            if selectedCategory == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Divider()

                    ForEach(LogCategory.allCases) { category in
                        Button {
                            selectedCategory = category
                        } label: {
                            HStack {
                                Label(category.rawValue, systemImage: category.systemImage)
                                if selectedCategory == category {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: selectedCategory?.systemImage ?? "line.3.horizontal.decrease.circle")
                        Text(selectedCategory?.rawValue ?? "All Subsystems")
                            .font(.caption2)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                // Filter / Search Field
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    TextField("Filter...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.caption2)
                        .frame(width: 90)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                )

                Text("•")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Button(action: copyAllLogs) {
                    HStack(spacing: 4) {
                        Image(systemName: hasCopied ? "checkmark" : "doc.on.doc")
                        Text(hasCopied ? "Copied" : "Copy")
                    }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(hasCopied ? Color.green : Color.secondary)
                .disabled(filteredEntries.isEmpty)

                Text("•")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Menu {
                    if let category = selectedCategory {
                        Button("Clear \(category.rawValue) Logs") {
                            logger.clear(category: category)
                        }
                    }
                    Button("Clear All Logs") {
                        logger.clear()
                    }
                } label: {
                    Text("Clear")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .disabled(logger.entries.isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)

            // Console Output Scroll Area
            ScrollViewReader { proxy in
                ScrollView {
                    if filteredEntries.isEmpty {
                        Text(logger.entries.isEmpty ? "Console is empty." : "No logs matching current filter.")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Color.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    } else {
                        Text(attributedLogText)
                            .font(.system(.caption2, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .id("bottom")
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
                .onChange(of: filteredEntries.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .contextMenu {
            Button("Copy Filtered Logs") {
                copyAllLogs()
            }
            .disabled(filteredEntries.isEmpty)

            Button("Copy All Logs") {
                copyEntireLogHistory()
            }
            .disabled(logger.entries.isEmpty)

            Divider()

            if let category = selectedCategory {
                Button("Clear \(category.rawValue) Logs") {
                    logger.clear(category: category)
                }
            }

            Button("Clear All Logs") {
                logger.clear()
            }
            .disabled(logger.entries.isEmpty)
        }
    }

    private var attributedLogText: AttributedString {
        var combined = AttributedString()
        for (index, entry) in filteredEntries.enumerated() {
            if index > 0 {
                combined.append(AttributedString("\n"))
            }

            var timeAttr = AttributedString("[\(entry.timestampString)] ")
            timeAttr.foregroundColor = .gray

            var catAttr = AttributedString("[\(entry.category.rawValue)] ")
            catAttr.foregroundColor = categoryColor(for: entry.category)
            catAttr.inlinePresentationIntent = .stronglyEmphasized

            combined.append(timeAttr)
            combined.append(catAttr)

            if entry.level != .info {
                var levelAttr = AttributedString("[\(entry.level.rawValue)] ")
                levelAttr.foregroundColor = levelColor(for: entry.level)
                levelAttr.inlinePresentationIntent = .stronglyEmphasized
                combined.append(levelAttr)
            }

            var msgAttr = AttributedString(entry.message)
            msgAttr.foregroundColor = entryColor(for: entry)
            combined.append(msgAttr)
        }
        return combined
    }

    private func categoryColor(for category: LogCategory) -> Color {
        switch category {
        case .plugins: return .green
        case .scenery: return .yellow
        case .aircraft: return .blue
        case .lua: return .purple
        case .updates: return .orange
        case .csl: return .cyan
        case .launch: return .mint
        case .system: return .indigo
        case .general: return .gray
        }
    }

    private func levelColor(for level: LogLevel) -> Color {
        switch level {
        case .error: return .red
        case .warn: return .yellow
        case .info: return .secondary
        case .debug: return .purple
        }
    }

    private func entryColor(for entry: LogEntry) -> Color {
        switch entry.level {
        case .error: return .red
        case .warn: return .yellow
        case .debug: return .secondary
        case .info: return Color.green
        }
    }

    private func copyAllLogs() {
        guard !filteredEntries.isEmpty else { return }
        let text = filteredEntries.map(\.formatted).joined(separator: "\n")
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

    private func copyEntireLogHistory() {
        guard !logger.entries.isEmpty else { return }
        let text = logger.entries.map(\.formatted).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard !filteredEntries.isEmpty else { return }
        DispatchQueue.main.async {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
}
