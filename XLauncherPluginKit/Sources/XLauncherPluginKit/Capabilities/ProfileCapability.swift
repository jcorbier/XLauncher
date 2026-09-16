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

import Foundation

/// Summary representation of an add-on profile in XLauncher.
public struct PluginProfileSummary: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let aircraftCount: Int
    public let totalAddonsCount: Int

    public init(
        id: UUID,
        name: String,
        aircraftCount: Int = 0,
        totalAddonsCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.aircraftCount = aircraftCount
        self.totalAddonsCount = totalAddonsCount
    }
}

/// Host-provided interface for inspecting and switching profiles.
public protocol PluginProfileProvider: Sendable {
    /// Returns the list of profiles available in the host.
    func availableProfiles() async -> [PluginProfileSummary]

    /// Returns the active profile ID, or nil for None / Custom.
    func activeProfileId() async -> UUID?

    /// Selects and activates a profile in the host.
    func selectProfile(id: UUID?) async throws
}

public extension Notification.Name {
    /// Notification posted when the active profile changes in the host.
    static let pluginActiveProfileDidChange = Notification.Name("com.jcorbier.XLauncher.activeProfileDidChange")
}
