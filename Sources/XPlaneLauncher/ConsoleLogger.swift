//
//  ConsoleLogger.swift
//  XPlaneLauncher
//

import Foundation
import SwiftUI

@MainActor
@Observable
class ConsoleLogger {
    var entries: [String] = []
    let maxEntries: Int
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
    
    init(maxEntries: Int = 500) {
        self.maxEntries = maxEntries
    }
    
    func log(_ message: String) {
        let timestamp = Self.dateFormatter.string(from: Date())
        let entry = "[\(timestamp)] \(message)"
        print(entry)
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }
    
    func clear() {
        entries.removeAll()
    }
}
