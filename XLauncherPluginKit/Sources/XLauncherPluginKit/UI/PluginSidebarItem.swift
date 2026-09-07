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

public enum PluginSidebarSection: Hashable, Sendable {
    case main
    case flight
    case updates
    case tools
    case system
    case custom(title: String)

    public var title: String {
        switch self {
        case .main: return "Add-ons"
        case .flight: return "Flight"
        case .updates: return "Updates"
        case .tools: return "Tools"
        case .system: return "System"
        case .custom(let title): return title
        }
    }
}

public struct PluginSidebarItem: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let section: PluginSidebarSection
    public let priority: Int
    public let badgeText: (@Sendable () -> String?)?
    public let viewBuilder: @MainActor @Sendable () -> AnyView

    public init(
        id: String,
        title: String,
        systemImage: String,
        section: PluginSidebarSection = .tools,
        priority: Int = 100,
        badgeText: (@Sendable () -> String?)? = nil,
        viewBuilder: @escaping @MainActor @Sendable () -> AnyView
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.section = section
        self.priority = priority
        self.badgeText = badgeText
        self.viewBuilder = viewBuilder
    }
}
