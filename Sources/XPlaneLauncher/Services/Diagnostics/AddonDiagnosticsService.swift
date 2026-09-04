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

final class AddonDiagnosticsService: Sendable {
    static let shared = AddonDiagnosticsService()

    private let machOAnalyzer = MachOAnalyzer.shared
    private let pathService = PathService.shared
    private var fileManager: FileManager { FileManager.default }

    init() {}

    // MARK: - Curated Known Library Registry

    struct KnownLibrary: Codable, Sendable {
        let identifier: String
        let name: String
        let prefixKeys: [String]
        let downloadURL: URL?

        init(identifier: String, name: String, prefixKeys: [String], downloadURL: URL?) {
            self.identifier = identifier
            self.name = name
            self.prefixKeys = prefixKeys
            self.downloadURL = downloadURL
        }
    }

    static let knownLibraries: [KnownLibrary] = loadKnownLibraries()
    static var curatedLibraries: [KnownLibrary] { knownLibraries }

    static func loadKnownLibraries() -> [KnownLibrary] {
        var candidates: [URL?] = [
            Bundle.main.url(forResource: "known_libraries", withExtension: "json"),
            Bundle.main.resourceURL?.appendingPathComponent("known_libraries.json")
        ]
        #if SWIFT_PACKAGE
        candidates.append(Bundle.module.url(forResource: "known_libraries", withExtension: "json"))
        #endif

        for case let candidateURL? in candidates {
            if FileManager.default.fileExists(atPath: candidateURL.path),
               let data = try? Data(contentsOf: candidateURL),
               let decoded = try? JSONDecoder().decode([KnownLibrary].self, from: data) {
                return decoded
            }
        }

        return fallbackLibraries
    }

    static let fallbackLibraries: [KnownLibrary] = [
        KnownLibrary(
            identifier: "opensceneryx",
            name: "OpenSceneryX",
            prefixKeys: ["opensceneryx", "open_scenery_x"],
            downloadURL: URL(string: "https://www.opensceneryx.com/")
        ),
        KnownLibrary(
            identifier: "misterx_library",
            name: "MisterX Library",
            prefixKeys: ["misterx_library", "misterx", "mister_x"],
            downloadURL: URL(string: "https://forums.x-plane.org/index.php?/files/file/28167-misterx-library-and-static-aircraft-extension/")
        ),
        KnownLibrary(
            identifier: "sam_library",
            name: "Scenery Animation Manager (SAM)",
            prefixKeys: ["sam_library", "sam_seasons", "sam_developer_pack"],
            downloadURL: URL(string: "https://stairport-sceneries.com/")
        ),
        KnownLibrary(
            identifier: "ra_library",
            name: "RA Library",
            prefixKeys: ["ra_library", "ra_lib"],
            downloadURL: URL(string: "https://forums.x-plane.org/index.php?/files/file/45410-ra-library/")
        ),
        KnownLibrary(
            identifier: "cdb_library",
            name: "CDB-Library",
            prefixKeys: ["cdb_library", "cdb"],
            downloadURL: URL(string: "https://forums.x-plane.org/index.php?/files/file/27907-cdb-library/")
        ),
        KnownLibrary(
            identifier: "ff_library",
            name: "FF Library Extended",
            prefixKeys: ["ff_library", "fflibrary", "ff_lod"],
            downloadURL: URL(string: "https://forums.x-plane.org/index.php?/files/file/12708-ff-library-extended/")
        ),
        KnownLibrary(
            identifier: "handyobjects",
            name: "HandyObjects Library",
            prefixKeys: ["handyobjects", "handy_objects"],
            downloadURL: URL(string: "https://forums.x-plane.org/index.php?/files/file/18653-handyobjects-library/")
        ),
        KnownLibrary(
            identifier: "flyagi_vegetation",
            name: "FlyAgi Vegetation Library",
            prefixKeys: ["flyagi_vegetation", "flyagi_trees"],
            downloadURL: URL(string: "https://forums.x-plane.org/index.php?/files/file/45370-flyagi-vegetation-global-trees/")
        ),
        KnownLibrary(
            identifier: "3d_people_library",
            name: "3D People Library",
            prefixKeys: ["3d_people_library", "3dpeople", "people_lib"],
            downloadURL: URL(string: "https://forums.x-plane.org/index.php?/files/file/26611-3d-people-library/")
        ),
        KnownLibrary(
            identifier: "puf_libs",
            name: "PuF Libs",
            prefixKeys: ["puf_libs", "puflib"],
            downloadURL: URL(string: "https://forums.x-plane.org/index.php?/files/file/71360-puf-libs/")
        ),
        KnownLibrary(
            identifier: "faib_aircraft",
            name: "FAIB Aircraft Library",
            prefixKeys: ["the_faib_aircraft_library", "faib_aircraft", "faib"],
            downloadURL: URL(string: "https://forums.x-plane.org/index.php?/files/file/52250-the-faib-aircraft-library/")
        ),
        KnownLibrary(
            identifier: "bs2001_library",
            name: "BS2001 Object Library",
            prefixKeys: ["bs2001_object_library", "bs2001_objects", "bs2001", "bs2001 object library"],
            downloadURL: URL(string: "https://forums.x-plane.org/index.php?/files/file/28045-bs2001-object-library/")
        ),
        KnownLibrary(
            identifier: "pm_library",
            name: "PM Library",
            prefixKeys: ["pm_library", "pm_objects"],
            downloadURL: URL(string: "https://forums.x-plane.org/index.php?/files/file/44795-pm-library/")
        ),
        KnownLibrary(
            identifier: "gt_library",
            name: "GT Library",
            prefixKeys: ["gt_library", "gt_building"],
            downloadURL: URL(string: "https://forums.x-plane.org/index.php?/files/file/71239-gt-library/")
        ),
        KnownLibrary(
            identifier: "re_library",
            name: "RE Library",
            prefixKeys: ["re_library", "re_airports"],
            downloadURL: URL(string: "https://forums.x-plane.org/index.php?/files/file/24722-re-library/")
        ),
        KnownLibrary(
            identifier: "ruscenery",
            name: "RuScenery",
            prefixKeys: ["ruscenery"],
            downloadURL: URL(string: "https://ruscenery.x-air.ru/")
        ),
        KnownLibrary(
            identifier: "flags_of_the_world",
            name: "Flags of the World",
            prefixKeys: ["flags_of_the_world", "flags_world"],
            downloadURL: URL(string: "https://forums.x-plane.org/index.php?/files/file/17090-flags-of-the-world/")
        ),
        KnownLibrary(
            identifier: "world_models",
            name: "World Models Library",
            prefixKeys: ["world_models", "worldmodels"],
            downloadURL: URL(string: "https://forums.x-plane.org/index.php?/files/file/32135-world-models-library/")
        ),
        KnownLibrary(
            identifier: "simheaven_xworld",
            name: "SimHeaven X-World",
            prefixKeys: ["simheaven", "x-world", "w2xp"],
            downloadURL: URL(string: "https://simheaven.com/")
        )
    ]

    // MARK: - Normalization Helper

    private func normalizeKey(_ string: String) -> String {
        string.lowercased().replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    // MARK: - Full Analysis Runner

    func runDiagnostics(
        xPlanePath: URL?,
        storagePools: [StoragePool],
        scenery: [PluginManager.Scenery],
        plugins: [PluginManager.Plugin],
        aircraft: [PluginManager.Aircraft],
        luaScripts: [PluginManager.LuaScript]
    ) async -> DiagnosticsReport {
        guard let xPlanePath = xPlanePath else {
            return DiagnosticsReport(
                timestamp: Date(),
                issues: [
                    DiagnosticIssue(
                        category: .addonIntegrity,
                        severity: .critical,
                        title: "X-Plane Directory Not Configured",
                        message: "Select your X-Plane 12 folder in Settings to enable add-on and scenery diagnostics."
                    )
                ]
            )
        }

        var issues: [DiagnosticIssue] = []

        // 1. Scenery Conflicts (Airport duplicates only; DSF mesh/ortho overlaps are standard in X-Plane)
        let customSceneryFolder = pathService.customSceneryFolder(for: xPlanePath)
        let (airportConflicts, airportIssues) = await analyzeAirportConflicts(in: customSceneryFolder, scenery: scenery)
        let (dsfOverlaps, _) = await analyzeDSFOverlaps(in: customSceneryFolder, scenery: scenery)
        issues.append(contentsOf: airportIssues)

        // 2. Missing Libraries
        let (missingLibraries, libraryIssues) = await analyzeMissingLibraries(in: customSceneryFolder, scenery: scenery)
        issues.append(contentsOf: libraryIssues)

        // 3. Add-on Integrity (Broken symlinks & Empty folders)
        let integrityIssues = await analyzeAddonIntegrity(
            xPlanePath: xPlanePath,
            storagePools: storagePools,
            plugins: plugins,
            aircraft: aircraft,
            scenery: scenery,
            luaScripts: luaScripts
        )
        issues.append(contentsOf: integrityIssues)

        // 4. Platform Compatibility (Mach-O checks for plugins)
        let compatibilityIssues = await analyzePluginCompatibility(
            xPlanePath: xPlanePath,
            plugins: plugins
        )
        issues.append(contentsOf: compatibilityIssues)

        return DiagnosticsReport(
            timestamp: Date(),
            issues: issues,
            airportConflicts: airportConflicts,
            dsfOverlaps: dsfOverlaps,
            missingLibraries: missingLibraries
        )
    }

    // MARK: - 1. Airport Conflicts

    func analyzeAirportConflicts(
        in customSceneryFolder: URL,
        scenery: [PluginManager.Scenery]
    ) async -> ([AirportConflict], [DiagnosticIssue]) {
        guard fileManager.fileExists(atPath: customSceneryFolder.path) else {
            return ([], [])
        }

        // Build priority index lookup from scenery_packs.ini order
        var iniOrder: [String: Int] = [:]
        var isEnabledLookup: [String: Bool] = [:]
        for (index, item) in scenery.enumerated() {
            iniOrder[item.folderName] = index
            isEnabledLookup[item.folderName] = item.isEnabled
        }

        // Map: ICAO -> [(folderName, airportName)]
        var icaoMap: [String: [(folderName: String, airportName: String?)]] = [:]

        // Enumerate packages in Custom Scenery
        let contents = (try? fileManager.contentsOfDirectory(at: customSceneryFolder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for packageURL in contents {
            let folderName = packageURL.lastPathComponent
            if folderName == "scenery_packs.ini" || folderName.hasPrefix("*") { continue }

            // Look for Earth nav data/apt.dat inside package
            let aptDatURL = packageURL.appendingPathComponent("Earth nav data").appendingPathComponent("apt.dat")
            if fileManager.fileExists(atPath: aptDatURL.path) {
                let airports = parseAirportICAOs(from: aptDatURL)
                for (icao, name) in airports {
                    icaoMap[icao, default: []].append((folderName, name))
                }
            }
        }

        var conflicts: [AirportConflict] = []
        var issues: [DiagnosticIssue] = []

        for (icao, declarations) in icaoMap {
            guard declarations.count > 1 else { continue }

            // Check if at least two declaring packs are enabled
            let enabledDeclarations = declarations.filter { isEnabledLookup[$0.folderName] ?? true }
            let hasActiveConflict = enabledDeclarations.count > 1

            // Sort packs by scenery_packs.ini priority (lower index = higher priority)
            let sortedPacks = declarations.sorted { a, b in
                let orderA = iniOrder[a.folderName] ?? Int.max
                let orderB = iniOrder[b.folderName] ?? Int.max
                return orderA < orderB
            }

            let primaryPack = sortedPacks.first?.folderName ?? ""
            let airportName = declarations.compactMap(\.airportName).first

            var conflictingPacks: [AirportConflict.ConflictingPack] = []
            for (idx, decl) in sortedPacks.enumerated() {
                conflictingPacks.append(AirportConflict.ConflictingPack(
                    folderName: decl.folderName,
                    iniIndex: iniOrder[decl.folderName],
                    isEnabled: isEnabledLookup[decl.folderName] ?? true,
                    isHigherPriority: idx == 0
                ))
            }

            let conflict = AirportConflict(
                icao: icao,
                airportName: airportName,
                declaringPacks: conflictingPacks
            )
            conflicts.append(conflict)

            if hasActiveConflict {
                let otherPacks = sortedPacks.dropFirst().map(\.folderName).joined(separator: ", ")
                let title = airportName != nil ? "Duplicate Airport: \(icao) (\(airportName!))" : "Duplicate Airport: \(icao)"
                let quickActionPack = sortedPacks.dropFirst().first?.folderName
                let quickAction = quickActionPack.map { DiagnosticQuickAction.disableScenery(folderName: $0) }

                issues.append(DiagnosticIssue(
                    category: .sceneryConflict,
                    severity: .warning,
                    title: title,
                    message: "Multiple active packages define airport '\(icao)'. '\(primaryPack)' takes priority due to its scenery_packs.ini order, shadowing: \(otherPacks).",
                    affectedAddonNames: sortedPacks.map(\.folderName),
                    details: sortedPacks.enumerated().map { i, p in
                        let priority = i == 0 ? "Active / Priority #1" : "Shadowed (#\(i + 1))"
                        let state = (isEnabledLookup[p.folderName] ?? true) ? "Enabled" : "Disabled"
                        return "\(p.folderName) [\(priority), \(state)]"
                    },
                    quickAction: quickAction,
                    quickActionTitle: quickActionPack.map { "Disable '\($0)'" }
                ))
            }
        }

        return (conflicts.sorted(by: { $0.icao < $1.icao }), issues)
    }

    /// Parses an `apt.dat` file extracting airport lines (row codes 1, 16, 17).
    func parseAirportICAOs(from aptDatURL: URL) -> [(icao: String, name: String?)] {
        guard let data = try? Data(contentsOf: aptDatURL),
              let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return []
        }

        var results: [(icao: String, name: String?)] = []
        var seenICAOs = Set<String>()

        content.enumerateLines { line, stop in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("I") || trimmed.hasPrefix("A") {
                return
            }

            // X-Plane airport row codes:
            // 1: Land airport
            // 16: Seaplane base
            // 17: Heliport
            // Format: 1 <elevation> <has_tower> <deprecated> <ICAO> <Name...>
            if trimmed.hasPrefix("1 ") || trimmed.hasPrefix("16 ") || trimmed.hasPrefix("17 ") {
                let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
                if parts.count >= 5 {
                    let icao = String(parts[4]).uppercased()
                    let name = parts.count >= 6 ? parts[5...].joined(separator: " ") : nil
                    if !seenICAOs.contains(icao) {
                        seenICAOs.insert(icao)
                        results.append((icao, name))
                    }
                }
            }
        }

        return results
    }

    // MARK: - 2. DSF Mesh/Tile Overlaps

    func analyzeDSFOverlaps(
        in customSceneryFolder: URL,
        scenery: [PluginManager.Scenery]
    ) async -> ([DSFOverlap], [DiagnosticIssue]) {
        guard fileManager.fileExists(atPath: customSceneryFolder.path) else {
            return ([], [])
        }

        var tileMap: [String: Set<String>] = [:]
        var isEnabledLookup: [String: Bool] = [:]
        for item in scenery {
            isEnabledLookup[item.folderName] = item.isEnabled
        }

        let packages = (try? fileManager.contentsOfDirectory(at: customSceneryFolder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for pkgURL in packages {
            let pkgName = pkgURL.lastPathComponent
            if pkgName == "scenery_packs.ini" || pkgName.hasPrefix("*") { continue }

            let earthNavDataURL = pkgURL.appendingPathComponent("Earth nav data")
            guard fileManager.fileExists(atPath: earthNavDataURL.path) else { continue }

            // Enumerate 10x10 latitude directories (e.g. +40-080)
            if let latDirs = try? fileManager.contentsOfDirectory(at: earthNavDataURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for latDir in latDirs {
                    guard latDir.hasDirectoryPath || (try? latDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                    if let dsfFiles = try? fileManager.contentsOfDirectory(at: latDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                        for dsf in dsfFiles where dsf.pathExtension.lowercased() == "dsf" {
                            let tileCoord = dsf.deletingPathExtension().lastPathComponent // e.g. "+48+002"
                            tileMap[tileCoord, default: []].insert(pkgName)
                        }
                    }
                }
            }
        }

        var overlaps: [DSFOverlap] = []

        for (tile, packs) in tileMap {
            guard packs.count > 1 else { continue }
            let packList = Array(packs).sorted()
            overlaps.append(DSFOverlap(tileCoordinates: tile, declaringPacks: packList))
        }

        // Note: Mesh, orthophoto, and overlay tile overlaps are standard layering behavior in X-Plane.
        // We track DSF overlaps in the report for informational diagnostics, but do not emit warning issues.
        return (overlaps.sorted(by: { $0.tileCoordinates < $1.tileCoordinates }), [])
    }

    // MARK: - 3. Missing Libraries

    func analyzeMissingLibraries(
        in customSceneryFolder: URL,
        scenery: [PluginManager.Scenery]
    ) async -> ([MissingLibraryRecord], [DiagnosticIssue]) {
        guard fileManager.fileExists(atPath: customSceneryFolder.path) else {
            return ([], [])
        }

        var installedLibraryFolders = Set<String>()

        // 1. Gather all installed package folder names in Custom Scenery
        let packages = (try? fileManager.contentsOfDirectory(at: customSceneryFolder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for pkgURL in packages {
            let pkgName = pkgURL.lastPathComponent
            if pkgName == "scenery_packs.ini" || pkgName.hasPrefix("*") { continue }
            installedLibraryFolders.insert(pkgName)
        }

        // Helper to check if a known library is installed
        func isLibraryInstalled(_ lib: KnownLibrary) -> Bool {
            let libKeys = (lib.prefixKeys + [lib.identifier, lib.name]).map { normalizeKey($0) }.filter { !$0.isEmpty }

            for folder in installedLibraryFolders {
                let normFolder = normalizeKey(folder)
                for key in libKeys {
                    if normFolder == key || normFolder.contains(key) {
                        return true
                    }
                }
            }

            return false
        }

        // Helper to check if a package is itself the library
        func isSelfLibrary(packageFolderName: String, lib: KnownLibrary) -> Bool {
            let normFolder = normalizeKey(packageFolderName)
            let libKeys = (lib.prefixKeys + [lib.identifier, lib.name]).map { normalizeKey($0) }.filter { !$0.isEmpty }
            for key in libKeys {
                if normFolder == key || normFolder.contains(key) {
                    return true
                }
            }
            return false
        }

        // 2. Scan active scenery packages for references to known libraries
        var referencedBy: [String: Set<String>] = [:] // library.identifier -> Set<packFolderName>

        for item in scenery where item.isEnabled {
            let packURL = customSceneryFolder.appendingPathComponent(item.folderName)
            guard fileManager.fileExists(atPath: packURL.path) else { continue }

            var textToCheck = ""

            // Inspect package's library.txt if present
            let packLibTxt = packURL.appendingPathComponent("library.txt")
            if let data = try? Data(contentsOf: packLibTxt),
               let str = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                textToCheck += str
            }

            // Inspect top-level manifests or readmes
            for name in ["scenery_pack.txt", "readme.txt", "manifest.txt"] {
                let manifestURL = packURL.appendingPathComponent(name)
                if let data = try? Data(contentsOf: manifestURL),
                   let str = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                    textToCheck += "\n" + str
                }
            }

            // Also check Earth nav data definitions if any text files exist
            let earthNavData = packURL.appendingPathComponent("Earth nav data")
            if let files = try? fileManager.contentsOfDirectory(at: earthNavData, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for file in files where file.pathExtension.lowercased() == "txt" {
                    if let data = try? Data(contentsOf: file),
                       let str = String(data: data, encoding: .utf8) {
                        textToCheck += "\n" + str
                    }
                }
            }

            let lowerText = textToCheck.lowercased()
            for knownLib in Self.curatedLibraries {
                // Never report a library package as missing itself
                if isSelfLibrary(packageFolderName: item.folderName, lib: knownLib) {
                    continue
                }

                if !isLibraryInstalled(knownLib) {
                    for key in knownLib.prefixKeys {
                        if lowerText.contains(key.lowercased()) {
                            referencedBy[knownLib.identifier, default: []].insert(item.folderName)
                            break
                        }
                    }
                }
            }
        }

        var records: [MissingLibraryRecord] = []
        var issues: [DiagnosticIssue] = []

        for (libId, packs) in referencedBy {
            guard let known = Self.curatedLibraries.first(where: { $0.identifier == libId }) else { continue }
            let packNames = Array(packs).sorted()
            let record = MissingLibraryRecord(
                identifier: known.identifier,
                name: known.name,
                downloadURL: known.downloadURL,
                referencedByPacks: packNames
            )
            records.append(record)

            let action = known.downloadURL.map { DiagnosticQuickAction.openURL(url: $0) }
            issues.append(DiagnosticIssue(
                category: .missingLibrary,
                severity: .warning,
                title: "Missing Scenery Library: \(known.name)",
                message: "The scenery package(s) \(packNames.joined(separator: ", ")) reference '\(known.name)', but this library is not installed in Custom Scenery. Objects or buildings may be missing in the simulator.",
                affectedAddonNames: packNames,
                details: [
                    "Required Library: \(known.name)",
                    "Referenced by: \(packNames.joined(separator: ", "))",
                    "Download URL: \(known.downloadURL?.absoluteString ?? "N/A")"
                ],
                quickAction: action,
                quickActionTitle: "Download \(known.name)"
            ))
        }

        return (records.sorted(by: { $0.name < $1.name }), issues)
    }

    private func parseLibraryPrefixes(from libTxtURL: URL) -> Set<String>? {
        guard let data = try? Data(contentsOf: libTxtURL),
              let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return nil
        }

        var prefixes = Set<String>()
        content.enumerateLines { line, stop in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Lines starting with EXPORT or EXPORT_EXTEND
            if trimmed.hasPrefix("EXPORT ") || trimmed.hasPrefix("EXPORT_EXTEND ") {
                let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
                if parts.count >= 2 {
                    let exportPath = String(parts[1])
                    let topDir = exportPath.split(separator: "/").first.map(String.init) ?? exportPath
                    prefixes.insert(topDir.lowercased())
                }
            }
        }
        return prefixes
    }

    // MARK: - 4. Add-on Integrity

    func analyzeAddonIntegrity(
        xPlanePath: URL,
        storagePools: [StoragePool],
        plugins: [PluginManager.Plugin],
        aircraft: [PluginManager.Aircraft],
        scenery: [PluginManager.Scenery],
        luaScripts: [PluginManager.LuaScript]
    ) async -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        // Check 1: Broken symlinks in X-Plane target folders
        let targetFolders: [(name: String, url: URL)] = [
            ("Plugins", pathService.pluginsTargetFolder(for: xPlanePath)),
            ("Aircraft", pathService.aircraftTargetFolder(for: xPlanePath)),
            ("Custom Scenery", pathService.customSceneryFolder(for: xPlanePath)),
            ("FlyWithLua Scripts", pathService.flyWithLuaScriptsFolder(for: xPlanePath))
        ]

        for (categoryName, folderURL) in targetFolders {
            guard fileManager.fileExists(atPath: folderURL.path),
                  let contents = try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
                continue
            }

            for itemURL in contents {
                var statBuf = stat()
                if lstat(itemURL.path, &statBuf) == 0 && (statBuf.st_mode & S_IFMT) == S_IFLNK {
                    let dest = try? fileManager.destinationOfSymbolicLink(atPath: itemURL.path)
                    let targetExists = fileManager.fileExists(atPath: itemURL.path)

                    if !targetExists {
                        let name = itemURL.lastPathComponent
                        issues.append(DiagnosticIssue(
                            category: .addonIntegrity,
                            severity: .warning,
                            title: "Broken Symlink: \(name) (\(categoryName))",
                            message: "The symlink '\(name)' points to a target destination that no longer exists on disk: '\(dest ?? "unknown")'.",
                            affectedAddonNames: [name],
                            details: [
                                "Folder: \(categoryName)",
                                "Symlink Path: \(itemURL.path)",
                                "Target Destination: \(dest ?? "N/A")"
                            ],
                            quickAction: .deleteItem(at: itemURL),
                            quickActionTitle: "Remove Broken Symlink"
                        ))
                    }
                }
            }
        }

        // Check 2: Empty folders in active storage pools
        for pool in storagePools where pool.isOnline {
            for sub in DataSubfolder.allCases {
                let subURL = pathService.dataFolder(sub, in: pool.url)
                guard fileManager.fileExists(atPath: subURL.path),
                      let addonFolders = try? fileManager.contentsOfDirectory(at: subURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
                    continue
                }

                for addonURL in addonFolders {
                    var isDir: ObjCBool = false
                    if fileManager.fileExists(atPath: addonURL.path, isDirectory: &isDir), isDir.boolValue {
                        let contents = (try? fileManager.contentsOfDirectory(at: addonURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                        if contents.isEmpty {
                            let name = addonURL.lastPathComponent
                            issues.append(DiagnosticIssue(
                                category: .addonIntegrity,
                                severity: .info,
                                title: "Empty Add-on Folder: \(name)",
                                message: "The directory '\(name)' inside storage pool '\(pool.name)' (\(sub.rawValue)) contains no files.",
                                affectedAddonNames: [name],
                                details: [
                                    "Storage Pool: \(pool.name)",
                                    "Path: \(addonURL.path)"
                                ],
                                quickAction: .deleteItem(at: addonURL),
                                quickActionTitle: "Delete Empty Folder"
                            ))
                        }
                    }
                }
            }
        }

        return issues
    }

    // MARK: - 5. Platform Compatibility (Mach-O checks)

    func analyzePluginCompatibility(
        xPlanePath: URL,
        plugins: [PluginManager.Plugin]
    ) async -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []
        let pluginsFolder = pathService.pluginsTargetFolder(for: xPlanePath)
        guard fileManager.fileExists(atPath: pluginsFolder.path) else { return [] }

        #if arch(arm64)
        let isAppleSilicon = true
        #else
        let isAppleSilicon = false
        #endif

        for plugin in plugins where plugin.isEnabled && !plugin.isOffline {
            let pluginDir = pluginsFolder.appendingPathComponent(plugin.folderName)
            guard fileManager.fileExists(atPath: pluginDir.path) else { continue }

            // Candidate .xpl paths in modern and legacy X-Plane plugin folder layouts:
            // 1. mac_x64/mac.xpl
            // 2. 64/mac.xpl
            // 3. mac.xpl
            let candidatePaths = [
                pluginDir.appendingPathComponent("mac_x64").appendingPathComponent("mac.xpl"),
                pluginDir.appendingPathComponent("64").appendingPathComponent("mac.xpl"),
                pluginDir.appendingPathComponent("mac.xpl")
            ]

            var foundMacBinaryURL: URL? = nil
            for candidate in candidatePaths {
                if fileManager.fileExists(atPath: candidate.path) {
                    foundMacBinaryURL = candidate
                    break
                }
            }

            if let macBinary = foundMacBinaryURL {
                if let analysis = machOAnalyzer.analyzeBinary(at: macBinary) {
                    if isAppleSilicon && !analysis.hasArm64 {
                        issues.append(DiagnosticIssue(
                            category: .compatibility,
                            severity: .warning,
                            title: "Intel-Only Plugin: \(plugin.name)",
                            message: "Plugin '\(plugin.name)' only provides an Intel (x86_64) binary. It will not load natively in X-Plane 12 on Apple Silicon unless the simulator is launched via Rosetta 2.",
                            affectedAddonNames: [plugin.name],
                            details: [
                                "Binary: \(macBinary.path)",
                                "Detected Architectures: \(analysis.displayDescription)",
                                "Recommended Action: Contact the developer for an Apple Silicon (arm64) update or launch X-Plane with Rosetta."
                            ],
                            quickAction: .disablePlugin(folderName: plugin.folderName),
                            quickActionTitle: "Disable Plugin"
                        ))
                    }
                }
            } else {
                // Check if plugin only has Windows (win.xpl) or Linux (lin.xpl)
                let winCandidates = [
                    pluginDir.appendingPathComponent("win_x64").appendingPathComponent("win.xpl"),
                    pluginDir.appendingPathComponent("64").appendingPathComponent("win.xpl"),
                    pluginDir.appendingPathComponent("win.xpl")
                ]
                let hasWin = winCandidates.contains { fileManager.fileExists(atPath: $0.path) }

                if hasWin {
                    issues.append(DiagnosticIssue(
                        category: .compatibility,
                        severity: .critical,
                        title: "Non-macOS Plugin: \(plugin.name)",
                        message: "Plugin '\(plugin.name)' contains Windows binaries (win.xpl) but no macOS dynamic library (mac.xpl). It cannot run on macOS.",
                        affectedAddonNames: [plugin.name],
                        details: ["Plugin Directory: \(pluginDir.path)"],
                        quickAction: .disablePlugin(folderName: plugin.folderName),
                        quickActionTitle: "Disable Plugin"
                    ))
                }
            }
        }

        return issues
    }
}
