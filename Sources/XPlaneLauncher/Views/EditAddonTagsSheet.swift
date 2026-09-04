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

struct EditAddonTagsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PluginManager.self) private var pluginManager

    let title: String
    let itemKey: String
    let detectedCategory: String
    let availableCategories: [String]
    let kindPrefix: String

    @State private var selectedCategory: String
    @State private var tags: [String]
    @State private var newTagText: String = ""

    init(
        title: String,
        itemKey: String,
        detectedCategory: String,
        availableCategories: [String],
        kindPrefix: String,
        currentCustomCategory: String?,
        currentTags: [String]
    ) {
        self.title = title
        self.itemKey = itemKey
        self.detectedCategory = detectedCategory
        self.availableCategories = availableCategories
        self.kindPrefix = kindPrefix
        _selectedCategory = State(initialValue: currentCustomCategory ?? "Auto")
        _tags = State(initialValue: currentTags)
    }

    private var suggestedTags: [String] {
        let all = pluginManager.allKnownTags(for: kindPrefix)
        return all.filter { !tags.contains($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Edit Category & Tags")
                        .font(.headline)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("Done") {
                    saveAndDismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Category Selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Category")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Picker("Category", selection: $selectedCategory) {
                            Text("Auto (\(detectedCategory))").tag("Auto")
                            Divider()
                            ForEach(availableCategories, id: \.self) { cat in
                                Text(cat).tag(cat)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: 260)
                    }

                    Divider()

                    // Tags Management
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Custom Tags")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        // Add new tag input
                        HStack(spacing: 8) {
                            TextField("Add a tag (e.g. Payware, Favorite, VFR)...", text: $newTagText)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    addNewTag()
                                }

                            Button("Add") {
                                addNewTag()
                            }
                            .disabled(newTagText.trimmingCharacters(in: .whitespaces).isEmpty)
                        }

                        // Current tags chips
                        if tags.isEmpty {
                            Text("No tags assigned yet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        } else {
                            FlowLayout(spacing: 6) {
                                ForEach(tags, id: \.self) { tag in
                                    HStack(spacing: 4) {
                                        Text(tag)
                                            .font(.caption)
                                            .fontWeight(.medium)

                                        Button(action: {
                                            tags.removeAll { $0 == tag }
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.15))
                                    .foregroundStyle(Color.accentColor)
                                    .clipShape(Capsule())
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        // Suggested / Previously Used Tags
                        if !suggestedTags.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Suggested Tags:")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                FlowLayout(spacing: 6) {
                                    ForEach(suggestedTags, id: \.self) { tag in
                                        Button(action: {
                                            tags.append(tag)
                                        }) {
                                            HStack(spacing: 3) {
                                                Image(systemName: "plus")
                                                    .font(.system(size: 9))
                                                Text(tag)
                                                    .font(.caption2)
                                            }
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(Color.secondary.opacity(0.12))
                                            .foregroundStyle(.secondary)
                                            .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.top, 6)
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 440, height: 340)
    }

    private func addNewTag() {
        let trimmed = newTagText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if !tags.contains(trimmed) {
            tags.append(trimmed)
        }
        newTagText = ""
    }

    private func saveAndDismiss() {
        let customCat = selectedCategory == "Auto" ? nil : selectedCategory
        pluginManager.setCustomCategory(customCat, for: itemKey)
        pluginManager.setTags(tags, for: itemKey)
        dismiss()
    }
}

// Simple flexible flow layout for tag chips
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width + spacing > maxWidth && rowWidth > 0 {
                height += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += size.width + (rowWidth > 0 ? spacing : 0)
                rowHeight = max(rowHeight, size.height)
            }
        }
        height += rowHeight
        return CGSize(width: maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
