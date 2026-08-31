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

            // Console Output Native NSTextView Area
            ConsoleTextViewRepresentable(
                entries: filteredEntries,
                isFilteredEmpty: filteredEntries.isEmpty,
                isLoggerEmpty: logger.entries.isEmpty
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
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
}

struct ConsoleTextViewRepresentable: NSViewRepresentable {
    let entries: [LogEntry]
    let isFilteredEmpty: Bool
    let isLoggerEmpty: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autoresizesSubviews = true

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.black.withAlphaComponent(0.9)
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.updateText(entries: entries, isFilteredEmpty: isFilteredEmpty, isLoggerEmpty: isLoggerEmpty)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.updateText(entries: entries, isFilteredEmpty: isFilteredEmpty, isLoggerEmpty: isLoggerEmpty)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    class Coordinator {
        weak var textView: NSTextView?
        private var lastRenderedEntriesCount: Int = 0
        private var lastRenderedFirstId: UUID?

        func updateText(entries: [LogEntry], isFilteredEmpty: Bool, isLoggerEmpty: Bool) {
            guard let textView = textView, let storage = textView.textStorage else { return }

            if isFilteredEmpty {
                lastRenderedEntriesCount = 0
                lastRenderedFirstId = nil
                let emptyMsg = isLoggerEmpty ? "Console is empty." : "No logs matching current filter."
                let attr = NSAttributedString(string: emptyMsg, attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                    .foregroundColor: NSColor.gray
                ])
                storage.setAttributedString(attr)
                return
            }

            let firstId = entries.first?.id
            let isIncremental = (firstId == lastRenderedFirstId && entries.count >= lastRenderedEntriesCount && lastRenderedEntriesCount > 0)

            if isIncremental {
                let newEntries = entries[lastRenderedEntriesCount...]
                if !newEntries.isEmpty {
                    let newAttr = buildAttributedString(for: Array(newEntries), leadingNewline: true)
                    storage.append(newAttr)
                    lastRenderedEntriesCount = entries.count
                    scrollToBottom()
                }
            } else {
                let fullAttr = buildAttributedString(for: entries, leadingNewline: false)
                storage.setAttributedString(fullAttr)
                lastRenderedEntriesCount = entries.count
                lastRenderedFirstId = firstId
                scrollToBottom()
            }
        }

        private func scrollToBottom() {
            guard let textView = textView else { return }
            textView.scrollToEndOfDocument(nil)
        }

        private func buildAttributedString(for entries: [LogEntry], leadingNewline: Bool) -> NSAttributedString {
            let result = NSMutableAttributedString()
            let fontRegular = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            let fontBold = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)

            for (index, entry) in entries.enumerated() {
                if leadingNewline || index > 0 {
                    result.append(NSAttributedString(string: "\n", attributes: [.font: fontRegular]))
                }

                let timeStr = NSAttributedString(string: "[\(entry.timestampString)] ", attributes: [
                    .font: fontRegular,
                    .foregroundColor: NSColor.gray
                ])
                result.append(timeStr)

                let catColor = nsCategoryColor(for: entry.category)
                let catStr = NSAttributedString(string: "[\(entry.category.rawValue)] ", attributes: [
                    .font: fontBold,
                    .foregroundColor: catColor
                ])
                result.append(catStr)

                if entry.level != .info {
                    let levelColor = nsLevelColor(for: entry.level)
                    let levelStr = NSAttributedString(string: "[\(entry.level.rawValue)] ", attributes: [
                        .font: fontBold,
                        .foregroundColor: levelColor
                    ])
                    result.append(levelStr)
                }

                let msgColor = nsEntryColor(for: entry)
                let msgStr = NSAttributedString(string: entry.message, attributes: [
                    .font: fontRegular,
                    .foregroundColor: msgColor
                ])
                result.append(msgStr)
            }
            return result
        }

        private func nsCategoryColor(for category: LogCategory) -> NSColor {
            switch category {
            case .profiles: return .systemBlue
            case .plugins: return .systemGreen
            case .scenery: return .systemYellow
            case .aircraft: return .systemTeal
            case .lua: return .systemPurple
            case .updates: return .systemOrange
            case .navdata: return .systemPink
            case .csl: return .systemCyan
            case .launch: return .systemMint
            case .system: return .systemIndigo
            case .general: return .systemGray
            }
        }

        private func nsLevelColor(for level: LogLevel) -> NSColor {
            switch level {
            case .error: return .systemRed
            case .warn: return .systemYellow
            case .info: return .secondaryLabelColor
            case .debug: return .systemPurple
            }
        }

        private func nsEntryColor(for entry: LogEntry) -> NSColor {
            switch entry.level {
            case .error: return .systemRed
            case .warn: return .systemYellow
            case .debug: return .secondaryLabelColor
            case .info: return .systemGreen
            }
        }
    }
}
