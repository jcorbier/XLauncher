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

struct ContentView: View {
    @Environment(PluginManager.self) var pluginManager
    @Environment(UpdateManager.self) var updateManager
    @State private var selectedCategory: NavigationCategory? = .aircraft
    
    enum NavigationCategory: String, CaseIterable, Identifiable {
        case aircraft = "Aircraft"
        case plugins = "Plugins"
        case scenery = "Scenery"
        case luaScripts = "Lua Scripts"
        case scripts = "Profile Scripts"
        case updates = "Updates"
        case settings = "Settings"
        
        var id: String { rawValue }
        
        var systemImage: String {
            switch self {
            case .aircraft: return "airplane"
            case .plugins: return "puzzlepiece.extension"
            case .scenery: return "map"
            case .luaScripts: return "scroll"
            case .scripts: return "terminal"
            case .updates: return "arrow.triangle.2.circlepath.circle"
            case .settings: return "gearshape"
            }
        }
        
        static var mainCategories: [NavigationCategory] {
            [.aircraft, .plugins, .scenery, .luaScripts, .scripts]
        }
        
        static var systemCategories: [NavigationCategory] {
            [.updates, .settings]
        }
        
        var isAddonCategory: Bool {
            NavigationCategory.mainCategories.contains(self)
        }
    }
    
    var availableUpdatesCount: Int {
        updateManager.updatableAddons.filter { $0.isUpdateAvailable }.count
    }
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedCategory) {
                Section("Add-ons") {
                    ForEach(NavigationCategory.mainCategories) { category in
                        NavigationLink(value: category) {
                            Label(category.rawValue, systemImage: category.systemImage)
                                .font(.body)
                        }
                    }
                }
                
                Section("System") {
                    ForEach(NavigationCategory.systemCategories) { category in
                        NavigationLink(value: category) {
                            HStack(spacing: 8) {
                                Label(category.rawValue, systemImage: category.systemImage)
                                    .font(.body)
                                
                                if category == .updates && availableUpdatesCount > 0 {
                                    Text("\(availableUpdatesCount)")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            VStack(spacing: 0) {
                // Header Profile Bar (Only shown for Add-ons categories)
                if let category = selectedCategory, category.isAddonCategory {
                    ProfileSelectorView()
                        .padding(12)
                    
                    Divider()
                }
                
                // Active Category View
                Group {
                    switch selectedCategory {
                    case .aircraft:
                        AircraftListView()
                    case .plugins:
                        PluginListView()
                    case .scenery:
                        SceneryListView()
                    case .luaScripts:
                        LuaScriptsListView()
                    case .scripts:
                        ScriptsListView()
                    case .updates:
                        UpdatesView()
                    case .settings:
                        SettingsView()
                    case .none:
                        ContentUnavailableView("Select a Category", systemImage: "sidebar.left")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                Divider()
                
                // Persistent Launch Footer Bar (Always Visible)
                HStack {
                    Spacer()
                    LaunchButton()
                        .frame(maxWidth: 320)
                    Spacer()
                }
                .padding(12)
                .background(Material.bar)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .task {
            updateManager.scanUpdatableAddons()
            updateManager.checkAllAddonUpdates()
        }
    }
}
