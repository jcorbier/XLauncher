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
import UniformTypeIdentifiers

extension Notification.Name {
    static let installAddonRequested = Notification.Name("installAddonRequested")
}

struct ContentView: View {
    @Environment(PluginManager.self) var pluginManager
    @Environment(UpdateManager.self) var updateManager
    @Environment(CSLManager.self) var cslManager
    @Environment(AppUpdateManager.self) var appUpdateManager
    @Environment(NavdataManager.self) var navdataManager
    @Binding var showWelcomeScreen: Bool
    @State private var selectedCategory: NavigationCategory? = .aircraft
    @State private var installerAnalysis: AddonPackageAnalysis? = nil
    @State private var isDropTargeted: Bool = false
    @State private var isShowingFileImporter: Bool = false

    init(showWelcomeScreen: Binding<Bool> = .constant(false)) {
        self._showWelcomeScreen = showWelcomeScreen
    }

    enum NavigationCategory: String, CaseIterable, Identifiable {
        case aircraft = "Aircraft"
        case plugins = "Plugins"
        case scenery = "Scenery"
        case luaScripts = "Lua Scripts"
        case scripts = "Profile Scripts"
        case addonUpdates = "Add-ons"
        case csl = "CSL Models"
        case navdata = "Navigation Data"
        case settings = "Settings"
        case about = "About"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .aircraft: return "airplane"
            case .plugins: return "puzzlepiece.extension"
            case .scenery: return "map"
            case .luaScripts: return "scroll"
            case .scripts: return "terminal"
            case .addonUpdates: return "arrow.triangle.2.circlepath.circle"
            case .csl: return "airplane.circle"
            case .navdata: return "point.topleft.down.to.point.bottomright.curvepath"
            case .settings: return "gearshape"
            case .about: return "info.circle"
            }
        }

        static var mainCategories: [NavigationCategory] {
            [.aircraft, .plugins, .scenery, .luaScripts, .scripts]
        }

        static func updateCategories(cslEnabled: Bool, navdataEnabled: Bool) -> [NavigationCategory] {
            var list: [NavigationCategory] = [.addonUpdates]
            if cslEnabled {
                list.append(.csl)
            }
            if navdataEnabled {
                list.append(.navdata)
            }
            return list
        }

        static var systemCategories: [NavigationCategory] {
            [.settings]
        }

        var isAddonCategory: Bool {
            self == .aircraft || self == .plugins || self == .scenery || self == .luaScripts || self == .scripts
        }
    }

    var availableUpdatesCount: Int {
        updateManager.updatableAddons.filter { $0.isUpdateAvailable }.count
    }

    var availableNavdataUpdatesCount: Int {
        navdataManager.addons.filter { $0.isUpdateAvailable }.count
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedCategory) {
                Section("Add-ons") {
                    ForEach(NavigationCategory.mainCategories) { category in
                        NavigationLink(value: category) {
                            HStack(spacing: 8) {
                                Label(category.rawValue, systemImage: category.systemImage)
                                    .font(.body)
                            }
                        }
                    }
                }

                Section("Updates") {
                    ForEach(NavigationCategory.updateCategories(cslEnabled: pluginManager.enableCSLSupport, navdataEnabled: pluginManager.enableNavdataSupport)) { category in
                        NavigationLink(value: category) {
                            HStack(spacing: 8) {
                                Label(category.rawValue, systemImage: category.systemImage)
                                    .font(.body)

                                if category == .addonUpdates {
                                    Spacer()

                                    if updateManager.isProcessing {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else if availableUpdatesCount > 0 {
                                        Text("\(availableUpdatesCount)")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.orange)
                                            .clipShape(Capsule())
                                    }
                                } else if category == .csl {
                                    Spacer()

                                    if cslManager.isProcessing {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else if cslManager.updatesAvailableCount > 0 {
                                        Text("\(cslManager.updatesAvailableCount)")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.orange)
                                            .clipShape(Capsule())
                                    }
                                } else if category == .navdata {
                                    Spacer()

                                    if navdataManager.isUpdatingAny || navdataManager.isFetchingPackages {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else if availableNavdataUpdatesCount > 0 {
                                        Text("\(availableNavdataUpdatesCount)")
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

                Section("System") {
                    ForEach(NavigationCategory.systemCategories) { category in
                        NavigationLink(value: category) {
                            HStack(spacing: 8) {
                                Label(category.rawValue, systemImage: category.systemImage)
                                    .font(.body)
                            }
                        }
                    }

                    Button(action: {
                        NSWorkspace.shared.open(AppInfo.documentationURL)
                    }) {
                        HStack(spacing: 8) {
                            Label("Help", systemImage: "questionmark.circle")
                                .font(.body)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    NavigationLink(value: NavigationCategory.about) {
                        HStack(spacing: 8) {
                            Label(NavigationCategory.about.rawValue, systemImage: NavigationCategory.about.systemImage)
                                .font(.body)

                            Spacer()

                            if appUpdateManager.isUpdateAvailable {
                                let tag = appUpdateManager.latestRelease?.tagName ?? ""
                                let badgeText = tag.isEmpty ? "NEW" : (tag.lowercased().hasPrefix("v") ? "NEW \(tag)" : "NEW v\(tag)")
                                Text(badgeText)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange)
                                    .clipShape(Capsule())
                                    .lineLimit(1)
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
                    case .addonUpdates:
                        UpdatesView()
                    case .csl:
                        CSLListView()
                    case .navdata:
                        NavdataListView()
                    case .settings:
                        SettingsView()
                    case .about:
                        AboutView()
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
            .overlay {
                if isDropTargeted {
                    ZStack {
                        Color.black.opacity(0.4)
                        VStack(spacing: 12) {
                            Image(systemName: "square.and.arrow.down.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.white)
                            Text("Drop Add-on Package to Install")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                            Text("Supports .zip archives, folders, and .lua scripts")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .padding(32)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(radius: 20)
                    }
                    .allowsHitTesting(false)
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .sheet(item: $installerAnalysis) { analysis in
            AddonInstallerView(analysis: analysis)
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.zip, .folder, .item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task { @MainActor in
                        await analyzeAndPresentInstaller(url: url)
                    }
                }
            case .failure(let error):
                pluginManager.lastErrorMessage = "Failed to select file: \(error.localizedDescription)"
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .installAddonRequested)) { _ in
            isShowingFileImporter = true
        }
        .sheet(isPresented: $showWelcomeScreen) {
            WelcomeView {
                updateManager.scanUpdatableAddons()
                updateManager.checkAutoUpdates()
                if pluginManager.enableCSLSupport && cslManager.automaticallyCheckCSLUpdates {
                    cslManager.cslFolderURL = pluginManager.cslPath
                    cslManager.xPlaneFolderURL = pluginManager.xPlanePath
                    cslManager.launcherDataFolder = pluginManager.launcherDataFolder
                    cslManager.scanAndCheck()
                }
                if pluginManager.enableNavdataSupport {
                    navdataManager.xPlaneURL = pluginManager.xPlanePath
                    Task {
                        await navdataManager.authManager.restoreSessionOnLaunch()
                        if case .authenticated = navdataManager.authManager.authState, navdataManager.automaticallyCheckNavdataUpdates {
                            await navdataManager.checkOnlinePackages()
                        }
                    }
                }
            }
        }
        .alert(
            "Add-on Management Error",
            isPresented: Binding(
                get: { pluginManager.lastErrorMessage != nil },
                set: { if !$0 { pluginManager.lastErrorMessage = nil } }
            )
        ) {
            Button("OK") {
                pluginManager.lastErrorMessage = nil
            }
        } message: {
            if let errorMsg = pluginManager.lastErrorMessage {
                Text(errorMsg)
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier("public.file-url") }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            var targetURL: URL?

            if let data = item as? Data {
                targetURL = URL(dataRepresentation: data, relativeTo: nil)
            } else if let url = item as? URL {
                targetURL = url
            }

            guard let url = targetURL else { return }

            Task { @MainActor in
                await analyzeAndPresentInstaller(url: url)
            }
        }
        return true
    }

    private func analyzeAndPresentInstaller(url: URL) async {
        do {
            let analysis = try await AddonInstallerService.shared.analyze(url: url)
            self.installerAnalysis = analysis
        } catch {
            pluginManager.lastErrorMessage = "Failed to analyze package: \(error.localizedDescription)"
        }
    }
}
