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

import XCTest
@testable import XPlaneLauncher

final class ZipExtractorSecurityTests: XCTestCase {

    var tempExtractDir: URL!

    override func setUp() {
        super.setUp()
        tempExtractDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("XLauncher_ZipExtract_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempExtractDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempExtractDir)
        super.tearDown()
    }

    /// Helper to create a minimal stored (compression 0) ZIP archive with arbitrary entry paths
    private func createTestZip(entries: [(path: String, content: String, isSymlink: Bool)]) -> Data {
        var data = Data()
        var centralDirectory = Data()
        var localOffsets: [Int] = []

        for entry in entries {
            localOffsets.append(data.count)
            let pathData = entry.path.data(using: .utf8)!
            let contentData = entry.content.data(using: .utf8)!
            let crc = calculateCRC32(contentData)

            // Local file header (30 bytes)
            data.append(contentsOf: [0x50, 0x4B, 0x03, 0x04]) // signature
            data.append(contentsOf: [20, 0]) // version needed (2.0)
            data.append(contentsOf: [0, 0])  // flags
            data.append(contentsOf: [0, 0])  // method (0 = Stored)
            data.append(contentsOf: [0, 0, 0, 0]) // mod time/date
            data.append(UInt32(crc).littleEndianData) // crc32
            data.append(UInt32(contentData.count).littleEndianData) // compressed size
            data.append(UInt32(contentData.count).littleEndianData) // uncompressed size
            data.append(UInt16(pathData.count).littleEndianData) // filename len
            data.append(contentsOf: [0, 0]) // extra len
            data.append(pathData)
            data.append(contentData)
        }

        let cdOffset = data.count

        for (index, entry) in entries.enumerated() {
            let pathData = entry.path.data(using: .utf8)!
            let contentData = entry.content.data(using: .utf8)!
            let crc = calculateCRC32(contentData)
            let localOffset = UInt32(localOffsets[index])

            // Unix mode in external attributes (bytes 38..41)
            // Symlink: 0o120000 << 16 = 0xA000_0000
            // Regular file: 0o100644 << 16 = 0x81A4_0000
            let externalAttr: UInt32 = entry.isSymlink ? 0xA1FF_0000 : 0x81A4_0000

            // Central directory header (46 bytes)
            centralDirectory.append(contentsOf: [0x50, 0x4B, 0x01, 0x02]) // signature
            centralDirectory.append(contentsOf: [0x1E, 0x03]) // version made by (Unix)
            centralDirectory.append(contentsOf: [20, 0]) // version needed
            centralDirectory.append(contentsOf: [0, 0])  // flags
            centralDirectory.append(contentsOf: [0, 0])  // method
            centralDirectory.append(contentsOf: [0, 0, 0, 0]) // mod time/date
            centralDirectory.append(UInt32(crc).littleEndianData)
            centralDirectory.append(UInt32(contentData.count).littleEndianData)
            centralDirectory.append(UInt32(contentData.count).littleEndianData)
            centralDirectory.append(UInt16(pathData.count).littleEndianData)
            centralDirectory.append(contentsOf: [0, 0]) // extra len
            centralDirectory.append(contentsOf: [0, 0]) // comment len
            centralDirectory.append(contentsOf: [0, 0]) // disk num start
            centralDirectory.append(contentsOf: [0, 0]) // internal attrs
            centralDirectory.append(externalAttr.littleEndianData) // external attrs
            centralDirectory.append(localOffset.littleEndianData) // local header offset
            centralDirectory.append(pathData)
        }

        let cdSize = centralDirectory.count
        data.append(centralDirectory)

        // End of central directory record (22 bytes)
        data.append(contentsOf: [0x50, 0x4B, 0x05, 0x06]) // signature
        data.append(contentsOf: [0, 0]) // disk number
        data.append(contentsOf: [0, 0]) // start disk
        data.append(UInt16(entries.count).littleEndianData) // entries on disk
        data.append(UInt16(entries.count).littleEndianData) // total entries
        data.append(UInt32(cdSize).littleEndianData) // cd size
        data.append(UInt32(cdOffset).littleEndianData) // cd offset
        data.append(contentsOf: [0, 0]) // comment len

        return data
    }

    private func calculateCRC32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0
        data.withUnsafeBytes { raw in
            if let base = raw.baseAddress?.assumingMemoryBound(to: Bytef.self) {
                crc = UInt32(crc32(0, base, uInt(data.count)))
            }
        }
        return crc
    }

    // MARK: - Security Tests

    func testExtractValidZip() throws {
        let zipData = createTestZip(entries: [
            (path: "addon/plugin.xpl", content: "binary", isSymlink: false),
            (path: "addon/readme.txt", content: "docs", isSymlink: false)
        ])

        XCTAssertNoThrow(try ZipExtractor.extract(data: zipData, to: tempExtractDir))

        let extractedFile = tempExtractDir.appendingPathComponent("addon/plugin.xpl")
        XCTAssertTrue(FileManager.default.fileExists(atPath: extractedFile.path))
    }

    func testRejectZipSlipPathTraversal() {
        let zipData = createTestZip(entries: [
            (path: "../evil.sh", content: "#!/bin/sh\nrm -rf /", isSymlink: false)
        ])

        XCTAssertThrowsError(try ZipExtractor.extract(data: zipData, to: tempExtractDir)) { error in
            guard case ZipExtractor.ZipError.pathTraversalAttempt = error else {
                XCTFail("Expected pathTraversalAttempt error, got \(error)")
                return
            }
        }
    }

    func testRejectNestedZipSlipTraversal() {
        let zipData = createTestZip(entries: [
            (path: "valid_dir/../../evil.sh", content: "exploit", isSymlink: false)
        ])

        XCTAssertThrowsError(try ZipExtractor.extract(data: zipData, to: tempExtractDir)) { error in
            guard case ZipExtractor.ZipError.pathTraversalAttempt = error else {
                XCTFail("Expected pathTraversalAttempt error, got \(error)")
                return
            }
        }
    }

    func testRejectArchiveWithSymbolicLinks() {
        let zipData = createTestZip(entries: [
            (path: "symlink_entry", content: "/etc/passwd", isSymlink: true)
        ])

        XCTAssertThrowsError(try ZipExtractor.extract(data: zipData, to: tempExtractDir)) { error in
            guard case ZipExtractor.ZipError.insecureArchive = error else {
                XCTFail("Expected insecureArchive error for symlink entry, got \(error)")
                return
            }
        }
    }
}

private extension UInt16 {
    var littleEndianData: Data {
        var val = self.littleEndian
        return Data(bytes: &val, count: MemoryLayout<UInt16>.size)
    }
}

private extension UInt32 {
    var littleEndianData: Data {
        var val = self.littleEndian
        return Data(bytes: &val, count: MemoryLayout<UInt32>.size)
    }
}

import zlib
