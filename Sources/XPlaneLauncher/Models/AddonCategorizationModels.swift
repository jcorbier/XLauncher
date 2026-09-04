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

enum AircraftCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case airliner = "Airliner"
    case generalAviation = "General Aviation"
    case military = "Military"
    case helicopter = "Helicopter"
    case other = "Other"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .airliner: return "airplane.departure"
        case .generalAviation: return "airplane"
        case .military: return "shield.checkered"
        case .helicopter: return "fan.desk"
        case .other: return "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .airliner: return .blue
        case .generalAviation: return .green
        case .military: return .red
        case .helicopter: return .orange
        case .other: return .secondary
        }
    }
}

enum SceneryTypeCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case airport = "Airports"
    case meshOrtho = "Mesh & Ortho"
    case landmark = "Landmarks"
    case library = "Libraries"
    case other = "Other"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .airport: return "airplane.arrival"
        case .meshOrtho: return "photo.stack"
        case .landmark: return "building.columns"
        case .library: return "building.2"
        case .other: return "map"
        }
    }

    var color: Color {
        switch self {
        case .airport: return .green
        case .meshOrtho: return .teal
        case .landmark: return .purple
        case .library: return .orange
        case .other: return .secondary
        }
    }
}

enum PluginTypeCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case traffic = "Traffic"
    case weather = "Weather & Environment"
    case sound = "Sound"
    case utilities = "Utilities & Tools"
    case other = "Other"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .traffic: return "airplane.circle"
        case .weather: return "cloud.sun.rain"
        case .sound: return "speaker.wave.2"
        case .utilities: return "wrench.and.screwdriver"
        case .other: return "puzzlepiece.extension"
        }
    }

    var color: Color {
        switch self {
        case .traffic: return .cyan
        case .weather: return .blue
        case .sound: return .pink
        case .utilities: return .indigo
        case .other: return .secondary
        }
    }
}

struct AddonCustomMetadata: Codable, Equatable, Sendable {
    var customCategory: String?
    var tags: [String]

    init(customCategory: String? = nil, tags: [String] = []) {
        self.customCategory = customCategory
        self.tags = tags
    }
}
