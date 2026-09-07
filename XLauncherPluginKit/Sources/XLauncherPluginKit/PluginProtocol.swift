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
import SwiftUI

public protocol XLauncherPlugin: AnyObject, Sendable {
    /// Static descriptor identifying this plugin
    static var descriptor: PluginDescriptor { get }

    /// Designated initializer
    init()

    /// Initializes plugin with runtime context from host
    func initialize(context: PluginContext) async throws

    /// Starts plugin background processes
    func start() async throws

    /// Stops plugin background processes
    func stop() async

    /// Sidebar items contributed by this plugin to the host UI
    var sidebarItems: [PluginSidebarItem] { get }

    /// Settings panes contributed by this plugin to host Preferences
    var settingsPanes: [PluginSettingsPane] { get }

    /// Optional launch button action override (e.g. "Start Flight")
    var launchActionOverride: LaunchActionOverride? { get }

    /// Dynamic capability query for specialized interfaces
    func capability<T>(_ capabilityType: T.Type) -> T?

    /// Notifies plugin that licensing state has changed (e.g. license activated/deactivated)
    func reloadLicenseState() async
}

public extension XLauncherPlugin {
    var sidebarItems: [PluginSidebarItem] { [] }
    var settingsPanes: [PluginSettingsPane] { [] }
    var launchActionOverride: LaunchActionOverride? { nil }
    func capability<T>(_ capabilityType: T.Type) -> T? { nil }
    func reloadLicenseState() async {}
}

public extension Notification.Name {
    static let pluginContributionsChanged = Notification.Name("com.jcorbier.XLauncher.pluginContributionsChanged")
}

