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

public enum PluginArchitecture: String, CaseIterable, Sendable, Comparable {
    case arm64 = "Apple Silicon (arm64)"
    case x86_64 = "Intel 64-bit (x86_64)"
    case i386 = "Legacy 32-bit (i386)"
    case unknown = "Unknown"

    public static func < (lhs: PluginArchitecture, rhs: PluginArchitecture) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct MachOAnalysisResult: Equatable, Sendable {
    public let architectures: Set<PluginArchitecture>

    public var hasArm64: Bool {
        architectures.contains(.arm64)
    }

    public var hasX86_64: Bool {
        architectures.contains(.x86_64)
    }

    public var isUniversal: Bool {
        hasArm64 && hasX86_64
    }

    public var isAppleSiliconNative: Bool {
        hasArm64
    }

    public var displayDescription: String {
        if isUniversal {
            return "Universal (arm64 + x86_64)"
        } else if hasArm64 {
            return "Apple Silicon (arm64)"
        } else if hasX86_64 {
            return "Intel 64-bit (x86_64 only)"
        } else {
            return architectures.map(\.rawValue).sorted().joined(separator: ", ")
        }
    }

    public init(architectures: Set<PluginArchitecture>) {
        self.architectures = architectures
    }
}

public final class MachOAnalyzer: Sendable {
    public static let shared = MachOAnalyzer()

    public init() {}

    private let MH_MAGIC_64: UInt32 = 0xFEEDFACF
    private let MH_CIGAM_64: UInt32 = 0xCFFAEDFE
    private let MH_MAGIC: UInt32 = 0xFEEDFACE
    private let MH_CIGAM: UInt32 = 0xCEFAEDFE
    private let FAT_MAGIC: UInt32 = 0xCAFEBABE
    private let FAT_CIGAM: UInt32 = 0xBEBAFECA
    private let FAT_MAGIC_64: UInt32 = 0xCAFEBABF
    private let FAT_CIGAM_64: UInt32 = 0xBFBAFECA

    private let CPU_TYPE_I386: UInt32 = 0x00000007
    private let CPU_TYPE_X86_64: UInt32 = 0x01000007
    private let CPU_TYPE_ARM: UInt32 = 0x0000000C
    private let CPU_TYPE_ARM64: UInt32 = 0x0100000C

    /// Inspects the header of an executable or dynamic library at the given URL to detect its Mach-O architectures.
    public func analyzeBinary(at url: URL) -> MachOAnalysisResult? {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? fileHandle.close() }

        guard let data = try? fileHandle.read(upToCount: 4096), data.count >= 8 else {
            return nil
        }

        return analyzeData(data)
    }

    /// Inspects Mach-O header bytes.
    public func analyzeData(_ data: Data) -> MachOAnalysisResult? {
        guard data.count >= 8 else { return nil }

        let magic = data.withUnsafeBytes { $0.load(as: UInt32.self) }
        var architectures = Set<PluginArchitecture>()

        switch magic {
        case MH_MAGIC_64, MH_CIGAM_64:
            // 64-bit thin Mach-O
            let isSwap = (magic == MH_CIGAM_64)
            var cputype = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }
            if isSwap { cputype = cputype.byteSwapped }
            if let arch = mapCpuType(cputype) {
                architectures.insert(arch)
            }

        case MH_MAGIC, MH_CIGAM:
            // 32-bit thin Mach-O
            let isSwap = (magic == MH_CIGAM)
            var cputype = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }
            if isSwap { cputype = cputype.byteSwapped }
            if let arch = mapCpuType(cputype) {
                architectures.insert(arch)
            }

        case FAT_MAGIC, FAT_CIGAM:
            // FAT binary (big endian or swapped)
            let isSwap = (magic == FAT_CIGAM)
            var nfat_arch = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }
            if isSwap {
                nfat_arch = nfat_arch.byteSwapped
            } else {
                nfat_arch = UInt32(bigEndian: nfat_arch)
            }

            let archCount = min(Int(nfat_arch), (data.count - 8) / 20)
            for i in 0..<archCount {
                let offset = 8 + (i * 20)
                guard offset + 4 <= data.count else { break }
                var cputype = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self) }
                if isSwap {
                    cputype = cputype.byteSwapped
                } else {
                    cputype = UInt32(bigEndian: cputype)
                }
                if let arch = mapCpuType(cputype) {
                    architectures.insert(arch)
                }
            }

        case FAT_MAGIC_64, FAT_CIGAM_64:
            // FAT 64-bit binary
            let isSwap = (magic == FAT_CIGAM_64)
            var nfat_arch = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }
            if isSwap {
                nfat_arch = nfat_arch.byteSwapped
            } else {
                nfat_arch = UInt32(bigEndian: nfat_arch)
            }

            let archCount = min(Int(nfat_arch), (data.count - 8) / 32)
            for i in 0..<archCount {
                let offset = 8 + (i * 32)
                guard offset + 4 <= data.count else { break }
                var cputype = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self) }
                if isSwap {
                    cputype = cputype.byteSwapped
                } else {
                    cputype = UInt32(bigEndian: cputype)
                }
                if let arch = mapCpuType(cputype) {
                    architectures.insert(arch)
                }
            }

        default:
            return nil
        }

        guard !architectures.isEmpty else { return nil }
        return MachOAnalysisResult(architectures: architectures)
    }

    private func mapCpuType(_ cputype: UInt32) -> PluginArchitecture? {
        switch cputype {
        case CPU_TYPE_ARM64:
            return .arm64
        case CPU_TYPE_X86_64:
            return .x86_64
        case CPU_TYPE_I386:
            return .i386
        default:
            return .unknown
        }
    }
}
