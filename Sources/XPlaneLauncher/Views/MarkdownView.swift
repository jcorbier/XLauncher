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

// MARK: - Markdown Block AST

enum MarkdownBlock: Identifiable, Hashable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case bulletItem(indent: Int, text: String)
    case numberedItem(number: String, indent: Int, text: String)
    case codeBlock(language: String?, code: String)
    case blockquote(text: String)
    case horizontalRule

    var id: String {
        switch self {
        case .heading(let level, let text):
            return "h-\(level)-\(text.hashValue)"
        case .paragraph(let text):
            return "p-\(text.hashValue)"
        case .bulletItem(let indent, let text):
            return "b-\(indent)-\(text.hashValue)"
        case .numberedItem(let number, let indent, let text):
            return "n-\(number)-\(indent)-\(text.hashValue)"
        case .codeBlock(let lang, let code):
            return "c-\(lang ?? "")-\(code.hashValue)"
        case .blockquote(let text):
            return "q-\(text.hashValue)"
        case .horizontalRule:
            return "hr-\(UUID().uuidString)"
        }
    }
}

// MARK: - Markdown Parser

struct MarkdownParser {
    static func parse(_ raw: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = raw.components(separatedBy: .newlines)

        var inCodeBlock = false
        var codeBlockLanguage: String? = nil
        var codeBlockLines: [String] = []

        var currentParagraph: [String] = []

        func flushParagraph() {
            if !currentParagraph.isEmpty {
                let joined = currentParagraph.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                if !joined.isEmpty {
                    blocks.append(.paragraph(text: joined))
                }
                currentParagraph.removeAll()
            }
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Code block fence
            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    // Close code block
                    blocks.append(.codeBlock(language: codeBlockLanguage, code: codeBlockLines.joined(separator: "\n")))
                    codeBlockLines.removeAll()
                    codeBlockLanguage = nil
                    inCodeBlock = false
                } else {
                    flushParagraph()
                    inCodeBlock = true
                    let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    codeBlockLanguage = lang.isEmpty ? nil : lang
                }
                continue
            }

            if inCodeBlock {
                codeBlockLines.append(line)
                continue
            }

            // Empty line separates blocks
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            // Horizontal rule
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(.horizontalRule)
                continue
            }

            // Headings
            if trimmed.hasPrefix("#") {
                flushParagraph()
                var level = 0
                for ch in trimmed {
                    if ch == "#" { level += 1 } else { break }
                }
                if level > 0 && level <= 6 {
                    let headerText = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                    blocks.append(.heading(level: level, text: headerText))
                    continue
                }
            }

            // Blockquote
            if trimmed.hasPrefix(">") {
                flushParagraph()
                let quoteText = String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces)
                blocks.append(.blockquote(text: quoteText))
                continue
            }

            // Bullet List Items
            let leadingSpaces = line.prefix(while: { $0 == " " || $0 == "\t" }).count
            let indentLevel = leadingSpaces / 2

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                flushParagraph()
                let itemText = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                blocks.append(.bulletItem(indent: indentLevel, text: itemText))
                continue
            }

            // Numbered List Items (e.g. "1. ")
            if let dotIndex = trimmed.firstIndex(of: "."),
               dotIndex < trimmed.index(trimmed.startIndex, offsetBy: min(4, trimmed.count)),
               let _ = Int(trimmed[..<dotIndex]) {
                let afterDot = trimmed[trimmed.index(after: dotIndex)...]
                if afterDot.hasPrefix(" ") {
                    flushParagraph()
                    let number = String(trimmed[..<dotIndex])
                    let itemText = afterDot.trimmingCharacters(in: .whitespaces)
                    blocks.append(.numberedItem(number: number, indent: indentLevel, text: itemText))
                    continue
                }
            }

            // Normal text line - buffer for paragraph
            currentParagraph.append(trimmed)
        }

        if inCodeBlock {
            blocks.append(.codeBlock(language: codeBlockLanguage, code: codeBlockLines.joined(separator: "\n")))
        }

        flushParagraph()
        return blocks
    }
}

// MARK: - Markdown View

struct MarkdownView: View {
    let markdown: String

    private var blocks: [MarkdownBlock] {
        MarkdownParser.parse(markdown)
    }

    private func attributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks.indices, id: \.self) { index in
                let block = blocks[index]
                switch block {
                case .heading(let level, let text):
                    VStack(alignment: .leading, spacing: 4) {
                        if index > 0 {
                            Spacer().frame(height: level <= 2 ? 10 : 4)
                        }
                        Text(attributed(text))
                            .font(fontForHeading(level: level))
                            .fontWeight(fontWeightForHeading(level: level))
                            .foregroundStyle(Color.primary)
                    }

                case .paragraph(let text):
                    Text(attributed(text))
                        .font(.body)
                        .foregroundStyle(Color.primary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                case .bulletItem(let indent, let text):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if indent > 0 {
                            Spacer().frame(width: CGFloat(indent * 14))
                        }
                        Image(systemName: indent == 0 ? "circle.fill" : "circle")
                            .font(.system(size: indent == 0 ? 5 : 4))
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)

                        Text(attributed(text))
                            .font(.body)
                            .foregroundStyle(Color.primary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                case .numberedItem(let number, let indent, let text):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if indent > 0 {
                            Spacer().frame(width: CGFloat(indent * 14))
                        }
                        Text("\(number).")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 16, alignment: .trailing)

                        Text(attributed(text))
                            .font(.body)
                            .foregroundStyle(Color.primary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                case .codeBlock(_, let code):
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(code)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.primary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                    )

                case .blockquote(let text):
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor.opacity(0.6))
                            .frame(width: 3)

                        Text(attributed(text))
                            .font(.body)
                            .italic()
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)

                case .horizontalRule:
                    Divider()
                        .padding(.vertical, 6)
                }
            }
        }
        .textSelection(.enabled)
    }

    private func fontForHeading(level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .title3
        case 3: return .headline
        case 4: return .subheadline
        default: return .body
        }
    }

    private func fontWeightForHeading(level: Int) -> Font.Weight {
        switch level {
        case 1: return .bold
        case 2: return .bold
        case 3: return .semibold
        default: return .medium
        }
    }
}
