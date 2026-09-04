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

public enum DiagnosticSeverity: String, Codable, Sendable, Comparable {
    case info = "Info"
    case warning = "Warning"
    case critical = "Critical"

    private var sortOrder: Int {
        switch self {
        case .info: return 0
        case .warning: return 1
        case .critical: return 2
        }
    }

    public static func < (lhs: DiagnosticSeverity, rhs: DiagnosticSeverity) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

public enum DiagnosticCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case sceneryConflict = "Scenery Conflicts"
    case missingLibrary = "Missing Libraries"
    case addonIntegrity = "Add-on Integrity"
    case compatibility = "Platform Compatibility"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .sceneryConflict: return "exclamationmark.triangle.fill"
        case .missingLibrary: return "books.vertical.fill"
        case .addonIntegrity: return "link.badge.plus"
        case .compatibility: return "cpu"
        }
    }
}

public enum DiagnosticQuickAction: Equatable, Sendable {
    case disableScenery(folderName: String)
    case disablePlugin(folderName: String)
    case openURL(url: URL)
    case deleteItem(at: URL)
}

public struct DiagnosticIssue: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let category: DiagnosticCategory
    public let severity: DiagnosticSeverity
    public let title: String
    public let message: String
    public let affectedAddonNames: [String]
    public let details: [String]
    public let quickAction: DiagnosticQuickAction?
    public let quickActionTitle: String?

    public init(
        id: UUID = UUID(),
        category: DiagnosticCategory,
        severity: DiagnosticSeverity,
        title: String,
        message: String,
        affectedAddonNames: [String] = [],
        details: [String] = [],
        quickAction: DiagnosticQuickAction? = nil,
        quickActionTitle: String? = nil
    ) {
        self.id = id
        self.category = category
        self.severity = severity
        self.title = title
        self.message = message
        self.affectedAddonNames = affectedAddonNames
        self.details = details
        self.quickAction = quickAction
        self.quickActionTitle = quickActionTitle
    }
}

public struct AirportConflict: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let icao: String
    public let airportName: String?
    public let declaringPacks: [ConflictingPack]

    public struct ConflictingPack: Identifiable, Equatable, Sendable {
        public var id: String { folderName }
        public let folderName: String
        public let iniIndex: Int?
        public let isEnabled: Bool
        public let isHigherPriority: Bool

        public init(folderName: String, iniIndex: Int?, isEnabled: Bool, isHigherPriority: Bool) {
            self.folderName = folderName
            self.iniIndex = iniIndex
            self.isEnabled = isEnabled
            self.isHigherPriority = isHigherPriority
        }
    }

    public init(
        id: UUID = UUID(),
        icao: String,
        airportName: String? = nil,
        declaringPacks: [ConflictingPack]
    ) {
        self.id = id
        self.icao = icao
        self.airportName = airportName
        self.declaringPacks = declaringPacks
    }
}

public struct DSFOverlap: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let tileCoordinates: String // e.g. "+48+002"
    public let declaringPacks: [String]

    public init(
        id: UUID = UUID(),
        tileCoordinates: String,
        declaringPacks: [String]
    ) {
        self.id = id
        self.tileCoordinates = tileCoordinates
        self.declaringPacks = declaringPacks
    }
}

public struct MissingLibraryRecord: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let identifier: String
    public let name: String
    public let downloadURL: URL?
    public let referencedByPacks: [String]

    public init(
        id: UUID = UUID(),
        identifier: String,
        name: String,
        downloadURL: URL? = nil,
        referencedByPacks: [String] = []
    ) {
        self.id = id
        self.identifier = identifier
        self.name = name
        self.downloadURL = downloadURL
        self.referencedByPacks = referencedByPacks
    }
}

public struct DiagnosticsReport: Equatable, Sendable {
    public let timestamp: Date
    public let issues: [DiagnosticIssue]
    public let airportConflicts: [AirportConflict]
    public let dsfOverlaps: [DSFOverlap]
    public let missingLibraries: [MissingLibraryRecord]

    public var criticalCount: Int {
        issues.filter { $0.severity == .critical }.count
    }

    public var warningCount: Int {
        issues.filter { $0.severity == .warning }.count
    }

    public var infoCount: Int {
        issues.filter { $0.severity == .info }.count
    }

    public var isClean: Bool {
        issues.isEmpty
    }

    public init(
        timestamp: Date = Date(),
        issues: [DiagnosticIssue] = [],
        airportConflicts: [AirportConflict] = [],
        dsfOverlaps: [DSFOverlap] = [],
        missingLibraries: [MissingLibraryRecord] = []
    ) {
        self.timestamp = timestamp
        self.issues = issues
        self.airportConflicts = airportConflicts
        self.dsfOverlaps = dsfOverlaps
        self.missingLibraries = missingLibraries
    }
}
