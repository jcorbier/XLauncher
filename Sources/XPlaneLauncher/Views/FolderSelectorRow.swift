//
//  MIT License
//  Copyright (c) 2026 Jeremie Corbier
//

import SwiftUI

struct FolderSelectorRow: View {
    let label: String
    let path: URL?
    let placeholder: String
    let action: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let path = path {
                    Text(path.path)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(path.path)
                } else {
                    Text(placeholder)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
            
            Spacer()
            
            Button("Change...") {
                action()
            }
        }
    }
}
