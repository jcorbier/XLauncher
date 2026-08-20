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
import zlib

/// A pure Swift in-process ZIP archive extractor supporting Store (0) and Deflate (8) compression methods.
public enum ZipExtractor {

    public enum ZipError: LocalizedError, Equatable {
        case invalidArchive
        case unsupportedCompressionMethod(UInt16)
        case decompressionFailed(Int32)
        case fileWriteFailed(String)
        case pathTraversalAttempt(String)
        case insecureArchive(String)
        case truncatedData

        public var errorDescription: String? {
            switch self {
            case .invalidArchive:
                return "The specified file is not a valid ZIP archive."
            case .unsupportedCompressionMethod(let method):
                return "Unsupported ZIP compression method: \(method). Only Stored (0) and Deflate (8) are supported."
            case .decompressionFailed(let code):
                return "ZIP decompression failed with zlib code: \(code)."
            case .fileWriteFailed(let path):
                return "Failed to write extracted file to: \(path)."
            case .pathTraversalAttempt(let entry):
                return "Insecure relative path in ZIP entry: \(entry)."
            case .insecureArchive(let reason):
                return "Insecure ZIP archive rejected: \(reason)"
            case .truncatedData:
                return "Unexpected end of ZIP archive data."
            }
        }
    }

    public struct ZipEntry: Sendable {
        public let path: String
        public let isDirectory: Bool
        public let isSymbolicLink: Bool
        public let uncompressedSize: UInt64
        public let compressedSize: UInt64
        public let compressionMethod: UInt16
        public let localHeaderOffset: UInt64
    }

    /// Extracts a ZIP archive file at `sourceURL` to `destinationURL`.
    /// - Parameters:
    ///   - sourceURL: The URL of the `.zip` file on disk.
    ///   - destinationURL: The directory where contents should be extracted.
    ///   - progressHandler: Optional callback reporting progress `(extractedCount, totalCount, currentFilename)`.
    public static func extract(
        archiveAt sourceURL: URL,
        to destinationURL: URL,
        progressHandler: (@Sendable (_ extractedCount: Int, _ totalCount: Int, _ currentFilename: String) -> Void)? = nil
    ) throws {
        let fileData = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
        try extract(data: fileData, to: destinationURL, progressHandler: progressHandler)
    }

    /// Extracts raw ZIP data to `destinationURL`.
    public static func extract(
        data: Data,
        to destinationURL: URL,
        progressHandler: (@Sendable (_ extractedCount: Int, _ totalCount: Int, _ currentFilename: String) -> Void)? = nil
    ) throws {
        let entries = try parseCentralDirectory(from: data)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        for (index, entry) in entries.enumerated() {
            // Reject symbolic link entries inside untrusted ZIP archives
            if entry.isSymbolicLink {
                throw ZipError.insecureArchive("Symbolic links inside archive are not allowed: \(entry.path)")
            }

            // Prevent Zip-Slip directory traversal using PathSecurity
            let targetURL: URL
            do {
                targetURL = try PathSecurity.validateSubpath(relativePath: entry.path, within: destinationURL)
            } catch {
                throw ZipError.pathTraversalAttempt(entry.path)
            }

            progressHandler?(index + 1, entries.count, entry.path)

            if entry.isDirectory {
                try fileManager.createDirectory(at: targetURL, withIntermediateDirectories: true)
                continue
            }

            // Ensure parent folder exists
            let parentURL = targetURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)

            // Extract file data
            let extractedData = try extractEntryData(entry: entry, from: data)
            try extractedData.write(to: targetURL, options: .atomic)
        }
    }

    /// Lists entries within a ZIP archive without extracting them.
    public static func listEntries(from sourceURL: URL) throws -> [ZipEntry] {
        let fileData = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
        return try parseCentralDirectory(from: fileData)
    }

    // MARK: - Internal Parsing & Decompression

    private static func parseCentralDirectory(from data: Data) throws -> [ZipEntry] {
        guard data.count >= 22 else { throw ZipError.invalidArchive }

        // Find End of Central Directory Record (EOCD signature: 0x06054b50)
        // Search backwards from the end of the file (up to 65536 + 22 bytes comment size)
        var eocdOffset: Int?
        let maxSearch = min(data.count, 65536 + 22)
        let searchStart = data.count - maxSearch

        for i in stride(from: data.count - 22, through: searchStart, by: -1) {
            if data[i] == 0x50 && data[i+1] == 0x4B && data[i+2] == 0x05 && data[i+3] == 0x06 {
                eocdOffset = i
                break
            }
        }

        guard let eocdPos = eocdOffset else {
            // Fallback: parse sequentially via local file headers if central directory is not found
            return try parseLocalHeadersSequentially(from: data)
        }

        let totalEntries = Int(data.readUInt16(at: eocdPos + 10))
        let cdSize = Int(data.readUInt32(at: eocdPos + 12))
        let cdOffset = Int(data.readUInt32(at: eocdPos + 16))

        guard cdOffset + cdSize <= data.count else {
            throw ZipError.invalidArchive
        }

        var entries: [ZipEntry] = []
        var currentOffset = cdOffset

        for _ in 0..<totalEntries {
            guard currentOffset + 46 <= data.count else { break }
            let sig = data.readUInt32(at: currentOffset)
            guard sig == 0x02014B50 else { break } // Central directory file header signature

            let method = data.readUInt16(at: currentOffset + 10)
            let compressedSize = UInt64(data.readUInt32(at: currentOffset + 20))
            let uncompressedSize = UInt64(data.readUInt32(at: currentOffset + 24))
            let filenameLength = Int(data.readUInt16(at: currentOffset + 28))
            let extraLength = Int(data.readUInt16(at: currentOffset + 30))
            let commentLength = Int(data.readUInt16(at: currentOffset + 32))
            let localHeaderOffset = UInt64(data.readUInt32(at: currentOffset + 42))

            let externalAttributes = data.readUInt32(at: currentOffset + 38)
            let isSymlink = ((externalAttributes >> 16) & 0o170000) == 0o120000

            let filenameOffset = currentOffset + 46
            guard filenameOffset + filenameLength <= data.count else { break }
            let filenameData = data.subdata(in: filenameOffset..<(filenameOffset + filenameLength))
            let filename = String(data: filenameData, encoding: .utf8)
                ?? String(data: filenameData, encoding: .ascii)
                ?? "file_\(entries.count)"

            let isDir = filename.hasSuffix("/") || filename.hasSuffix("\\")

            entries.append(ZipEntry(
                path: filename,
                isDirectory: isDir,
                isSymbolicLink: isSymlink,
                uncompressedSize: uncompressedSize,
                compressedSize: compressedSize,
                compressionMethod: method,
                localHeaderOffset: localHeaderOffset
            ))

            currentOffset += 46 + filenameLength + extraLength + commentLength
        }

        return entries
    }

    private static func parseLocalHeadersSequentially(from data: Data) throws -> [ZipEntry] {
        var entries: [ZipEntry] = []
        var offset = 0

        while offset + 30 <= data.count {
            let sig = data.readUInt32(at: offset)
            if sig == 0x02014B50 || sig == 0x06054B50 {
                // Reached central directory
                break
            }
            guard sig == 0x04034B50 else { break }

            let method = data.readUInt16(at: offset + 8)
            let compressedSize = UInt64(data.readUInt32(at: offset + 18))
            let uncompressedSize = UInt64(data.readUInt32(at: offset + 22))
            let filenameLen = Int(data.readUInt16(at: offset + 26))
            let extraLen = Int(data.readUInt16(at: offset + 28))

            let filenameOffset = offset + 30
            guard filenameOffset + filenameLen <= data.count else { break }
            let filenameData = data.subdata(in: filenameOffset..<(filenameOffset + filenameLen))
            let filename = String(data: filenameData, encoding: .utf8) ?? "file_\(entries.count)"
            let isDir = filename.hasSuffix("/") || filename.hasSuffix("\\")

            entries.append(ZipEntry(
                path: filename,
                isDirectory: isDir,
                isSymbolicLink: false,
                uncompressedSize: uncompressedSize,
                compressedSize: compressedSize,
                compressionMethod: method,
                localHeaderOffset: UInt64(offset)
            ))

            offset += 30 + filenameLen + extraLen + Int(compressedSize)
        }

        return entries
    }

    private static func extractEntryData(entry: ZipEntry, from data: Data) throws -> Data {
        let localOffset = Int(entry.localHeaderOffset)
        guard localOffset + 30 <= data.count else { throw ZipError.truncatedData }

        let sig = data.readUInt32(at: localOffset)
        guard sig == 0x04034B50 else { throw ZipError.invalidArchive }

        let filenameLen = Int(data.readUInt16(at: localOffset + 26))
        let extraLen = Int(data.readUInt16(at: localOffset + 28))

        let dataStart = localOffset + 30 + filenameLen + extraLen
        let dataEnd = dataStart + Int(entry.compressedSize)
        guard dataEnd <= data.count else { throw ZipError.truncatedData }

        let compressedData = data.subdata(in: dataStart..<dataEnd)

        switch entry.compressionMethod {
        case 0: // Stored (no compression)
            return compressedData

        case 8: // Deflated
            return try decompressDeflate(compressedData: compressedData, uncompressedSize: Int(entry.uncompressedSize))

        default:
            throw ZipError.unsupportedCompressionMethod(entry.compressionMethod)
        }
    }

    private static func decompressDeflate(compressedData: Data, uncompressedSize: Int) throws -> Data {
        if compressedData.isEmpty { return Data() }

        var stream = z_stream()
        // Window bits: -MAX_WBITS (-15) for raw DEFLATE without zlib/gzip headers
        let initStatus = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initStatus == Z_OK else {
            throw ZipError.decompressionFailed(initStatus)
        }
        defer { inflateEnd(&stream) }

        var destinationData = Data(count: max(uncompressedSize, 1024))
        var totalDecompressed = 0

        try compressedData.withUnsafeBytes { rawIn in
            guard let inBase = rawIn.baseAddress?.assumingMemoryBound(to: Bytef.self) else { return }
            stream.next_in = UnsafeMutablePointer(mutating: inBase)
            stream.avail_in = uInt(compressedData.count)

            while true {
                if totalDecompressed >= destinationData.count {
                    destinationData.count = max(destinationData.count * 2, totalDecompressed + 4096)
                }

                let remainingSpace = destinationData.count - totalDecompressed
                try destinationData.withUnsafeMutableBytes { rawOut in
                    guard let outBase = rawOut.baseAddress?.assumingMemoryBound(to: Bytef.self) else { return }
                    stream.next_out = outBase.advanced(by: totalDecompressed)
                    stream.avail_out = uInt(remainingSpace)

                    let status = inflate(&stream, Z_NO_FLUSH)
                    let written = remainingSpace - Int(stream.avail_out)
                    totalDecompressed += written

                    if status == Z_STREAM_END {
                        return
                    } else if status == Z_OK {
                        // Continue decompressing
                    } else if status == Z_BUF_ERROR && stream.avail_in == 0 {
                        return
                    } else {
                        throw ZipError.decompressionFailed(status)
                    }
                }

                if stream.avail_in == 0 && stream.avail_out > 0 {
                    break
                }
            }
        }

        destinationData.count = totalDecompressed
        return destinationData
    }
}

// MARK: - Data Byte Reading Helpers

private extension Data {
    func readUInt16(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self).littleEndian
        }
    }

    func readUInt32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian
        }
    }
}
