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

public struct FMSCycleInfo: Codable, Equatable, Hashable, Sendable {
    public let cycle: String
    public let cycleInternalId: String
    public let effective: String?
    public let end: String?
    public let description: String?

    enum CodingKeys: String, CodingKey {
        case cycle = "Cycle"
        case cycleInternalId = "CycleInternalId"
        case effective = "Effective"
        case end = "End"
        case description = "Description"
    }

    public init(
        cycle: String,
        cycleInternalId: String,
        effective: String? = nil,
        end: String? = nil,
        description: String? = nil
    ) {
        self.cycle = cycle
        self.cycleInternalId = cycleInternalId
        self.effective = effective
        self.end = end
        self.description = description
    }
}

public struct FMSAddonSearchEntry: Codable, Equatable, Hashable, Sendable {
    public let path: String
    public let filename: String

    public init(path: String, filename: String) {
        self.path = path
        self.filename = filename
    }
}

public struct FMSAddonMapping: Codable, Equatable, Hashable, Sendable {
    public let platform: String
    public let simulator: String
    public let directoryPath: String
    public let searches: [FMSAddonSearchEntry]

    public init(
        platform: String,
        simulator: String,
        directoryPath: String,
        searches: [FMSAddonSearchEntry] = []
    ) {
        self.platform = platform
        self.simulator = simulator
        self.directoryPath = directoryPath
        self.searches = searches
    }
}

public struct FMSAddonDefinition: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: String { guid }
    public let name: String
    public let guid: String
    public let cycle: String
    public let revision: String
    public let masterfile: String
    public let mappings: [FMSAddonMapping]

    public init(
        name: String,
        guid: String,
        cycle: String,
        revision: String,
        masterfile: String,
        mappings: [FMSAddonMapping]
    ) {
        self.name = name
        self.guid = guid
        self.cycle = cycle
        self.revision = revision
        self.masterfile = masterfile
        self.mappings = mappings
    }
}

public struct FMSCatalog: Equatable, Sendable {
    public let id: String
    public let cycle: String
    public let internalId: String
    public let fileRevision: String
    public let addons: [FMSAddonDefinition]

    public init(
        id: String,
        cycle: String,
        internalId: String,
        fileRevision: String,
        addons: [FMSAddonDefinition]
    ) {
        self.id = id
        self.cycle = cycle
        self.internalId = internalId
        self.fileRevision = fileRevision
        self.addons = addons
    }
}

public final class NavigraphAPIClient: Sendable {

    private let authManager: NavigraphAuthManager
    private let baseURL = URL(string: "https://www.navigraph.com/api/1")!

    public init(authManager: NavigraphAuthManager) {
        self.authManager = authManager
    }

    // MARK: - Current Cycle

    /// Fetches metadata for the current AIRAC cycle.
    public func fetchCurrentCycle() async throws -> FMSCycleInfo {
        let url = baseURL.appendingPathComponent("fmsdata/cycles/current")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "NavigraphAPI", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch current cycle information."])
        }

        return try JSONDecoder().decode(FMSCycleInfo.self, from: data)
    }

    // MARK: - Index Catalog (data.index XML)

    /// Fetches and parses the add-on index catalog (`data.index`), optionally saving the raw XML to a cache file.
    public func fetchCatalog(cacheDestinationURL: URL? = nil) async throws -> FMSCatalog {
        let indexMetaURL = baseURL.appendingPathComponent("fmsdata/index")
        var request = URLRequest(url: indexMetaURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let (metaData, metaResponse) = try await URLSession.shared.data(for: request)
        guard let metaHttp = metaResponse as? HTTPURLResponse, metaHttp.statusCode == 200 else {
            throw NSError(domain: "NavigraphAPI", code: (metaResponse as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch data index metadata."])
        }

        struct IndexMetaResponse: Codable {
            let Id: String
            let Comments: String?
            let Version: String?
            let Url: String
        }

        let indexMeta = try JSONDecoder().decode(IndexMetaResponse.self, from: metaData)
        guard let dataURL = URL(string: indexMeta.Url) else {
            throw NSError(domain: "NavigraphAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid data index download URL: \(indexMeta.Url)"])
        }

        var xmlRequest = URLRequest(url: dataURL)
        xmlRequest.httpMethod = "GET"
        xmlRequest.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let (xmlData, xmlResponse) = try await URLSession.shared.data(for: xmlRequest)
        guard let xmlHttp = xmlResponse as? HTTPURLResponse, xmlHttp.statusCode == 200 || xmlHttp.statusCode == 206 else {
            throw NSError(domain: "NavigraphAPI", code: (xmlResponse as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: "Failed to download data.index."])
        }

        if let cacheDestinationURL {
            try? FileManager.default.createDirectory(at: cacheDestinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? xmlData.write(to: cacheDestinationURL, options: .atomic)
        }

        return try FMSIndexXMLParser.parse(data: xmlData)
    }

    // MARK: - Download URL Generation

    /// Requests a package download URL for a given masterfile and cycle internal ID.
    public func requestDownloadURL(
        filename: String,
        internalId: String,
        preferredRegion: String? = nil
    ) async throws -> URL {
        guard let token = await authManager.token, !token.isEmpty else {
            throw NSError(domain: "NavigraphAPI", code: 401, userInfo: [NSLocalizedDescriptionKey: "You must be signed in to Navigraph to download navigation data."])
        }

        let userRegion = await authManager.currentUser?.preferredRegion
        let region = preferredRegion ?? userRegion ?? "EUC1"
        let downloadURL = baseURL.appendingPathComponent("download/\(region)/fmsdata/\(token)")

        var request = URLRequest(url: downloadURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let body: [String: String] = [
            "filename": filename,
            "internal_id": internalId.lowercased()
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)"
            throw NSError(domain: "NavigraphAPI", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: "Failed to request download URL: \(errorText)"])
        }

        struct DownloadResponse: Codable {
            let url: String
        }

        let downloadResp = try JSONDecoder().decode(DownloadResponse.self, from: data)
        guard let targetURL = URL(string: downloadResp.url) else {
            throw NSError(domain: "NavigraphAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid download URL in response: \(downloadResp.url)"])
        }

        return targetURL
    }

    // MARK: - File Download

    /// Downloads a zip package file to a temporary destination.
    public func downloadPackageFile(
        from url: URL,
        destinationURL: URL,
        progressHandler: (@Sendable (_ progress: Double, _ bytesReceived: Int64, _ totalBytes: Int64) -> Void)? = nil
    ) async throws {
        let delegate = FMSDownloadProgressDelegate(progressHandler: progressHandler)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        let (tempURL, response) = try await session.download(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 || httpResponse.statusCode == 206 else {
            throw NSError(domain: "NavigraphAPI", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: "Download failed with HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)"])
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: tempURL, to: destinationURL)
    }
}

// MARK: - Download Progress Delegate

private final class FMSDownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progressHandler: (@Sendable (Double, Int64, Int64) -> Void)?

    init(progressHandler: (@Sendable (Double, Int64, Int64) -> Void)?) {
        self.progressHandler = progressHandler
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) { }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler?(fraction, totalBytesWritten, totalBytesExpectedToWrite)
    }
}

// MARK: - XML Parser for data.index

public final class FMSIndexXMLParser: NSObject, XMLParserDelegate, @unchecked Sendable {

    public static func parse(data: Data) throws -> FMSCatalog {
        let parser = FMSIndexXMLParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser

        guard xmlParser.parse() else {
            throw xmlParser.parserError ?? NSError(domain: "XMLParser", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse data.index XML."])
        }

        return FMSCatalog(
            id: parser.catalogId,
            cycle: parser.catalogCycle,
            internalId: parser.catalogInternalId,
            fileRevision: parser.catalogFileRevision,
            addons: parser.addons
        )
    }

    private var catalogId: String = ""
    private var catalogCycle: String = ""
    private var catalogInternalId: String = ""
    private var catalogFileRevision: String = ""
    private var addons: [FMSAddonDefinition] = []

    // State
    private var currentAddonName: String = ""
    private var currentAddonGuid: String = ""
    private var currentAddonCycle: String = ""
    private var currentAddonRevision: String = ""
    private var currentAddonMasterfile: String = ""
    private var currentMappings: [FMSAddonMapping] = []

    private var currentMappingPlatform: String = ""
    private var currentMappingSimulator: String = ""
    private var currentMappingDir: String = ""
    private var currentSearches: [FMSAddonSearchEntry] = []

    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        switch elementName {
        case "addonIndexes":
            catalogId = attributeDict["id"] ?? ""
            catalogCycle = attributeDict["cycle"] ?? ""
            catalogInternalId = attributeDict["internalId"] ?? ""
            catalogFileRevision = attributeDict["fileRevision"] ?? ""

        case "addon":
            currentAddonName = attributeDict["name"] ?? ""
            currentAddonGuid = attributeDict["guid"] ?? ""
            currentAddonCycle = attributeDict["cycle"] ?? ""
            currentAddonRevision = attributeDict["revision"] ?? ""
            currentAddonMasterfile = attributeDict["masterfile"] ?? ""
            currentMappings = []

        case "mapping":
            currentMappingPlatform = attributeDict["platform"] ?? "ALL"
            currentMappingSimulator = attributeDict["simulator"] ?? "ALL"
            currentMappingDir = ""
            currentSearches = []

        case "directory":
            currentMappingDir = attributeDict["path"] ?? ""

        case "filesystem":
            let path = attributeDict["path"] ?? ""
            let filename = attributeDict["filename"] ?? ""
            currentSearches.append(FMSAddonSearchEntry(path: path, filename: filename))

        default:
            break
        }
    }

    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "mapping":
            let mapping = FMSAddonMapping(
                platform: currentMappingPlatform,
                simulator: currentMappingSimulator,
                directoryPath: currentMappingDir,
                searches: currentSearches
            )
            currentMappings.append(mapping)

        case "addon":
            let addon = FMSAddonDefinition(
                name: currentAddonName,
                guid: currentAddonGuid,
                cycle: currentAddonCycle,
                revision: currentAddonRevision,
                masterfile: currentAddonMasterfile,
                mappings: currentMappings
            )
            addons.append(addon)

        default:
            break
        }
    }
}

// MARK: - Package .index File Parser

public struct FMSPackageFileMapping: Sendable {
    public let source: String
    public let destination: String
    public let directory: String
}

public struct FMSPackageIndex: Sendable {
    public let addonName: String
    public let guid: String
    public let cycle: String
    public let revision: String
    public let fileMappings: [FMSPackageFileMapping]
}

public final class FMSPackageIndexParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    private let targetSimulator: String
    private var addonName = ""
    private var addonGuid = ""
    private var addonCycle = ""
    private var addonRevision = ""

    private var currentSimulator = ""
    private var currentDirectory = "."
    private var allMappings: [String: [FMSPackageFileMapping]] = [:]

    public init(targetSimulator: String = "XP12") {
        self.targetSimulator = targetSimulator
    }

    public static func parse(data: Data, simulator: String = "XP12") throws -> FMSPackageIndex {
        let parser = FMSPackageIndexParser(targetSimulator: simulator)
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        guard xmlParser.parse() else {
            throw xmlParser.parserError ?? NSError(domain: "FMSPackageIndexParser", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse package index XML."])
        }

        let selectedMappings = parser.allMappings[simulator]
            ?? parser.allMappings["XP11"]
            ?? parser.allMappings["ALL"]
            ?? parser.allMappings["USER"]
            ?? parser.allMappings.values.first
            ?? []

        return FMSPackageIndex(
            addonName: parser.addonName,
            guid: parser.addonGuid,
            cycle: parser.addonCycle,
            revision: parser.addonRevision,
            fileMappings: selectedMappings
        )
    }

    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        switch elementName {
        case "addon":
            addonName = attributeDict["name"] ?? ""
            addonGuid = attributeDict["guid"] ?? ""
            addonCycle = attributeDict["cycle"] ?? ""
            addonRevision = attributeDict["revision"] ?? ""

        case "mapping":
            currentSimulator = attributeDict["simulator"] ?? "ALL"

        case "directory":
            currentDirectory = attributeDict["name"] ?? "."

        case "files":
            let dest = attributeDict["destination"] ?? ""
            let src = attributeDict["source"] ?? ""
            if !dest.isEmpty && !src.isEmpty {
                let fileMapping = FMSPackageFileMapping(source: src, destination: dest, directory: currentDirectory)
                allMappings[currentSimulator, default: []].append(fileMapping)
            }

        default:
            break
        }
    }
}
