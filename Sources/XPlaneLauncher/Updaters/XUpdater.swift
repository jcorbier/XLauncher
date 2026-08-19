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
import CryptoKit
import zlib

private func decompressGzip(data: Data) -> Data? {
    guard data.count > 2, data.prefix(2) == Data([0x1f, 0x8b]) else {
        return data
    }

    var stream = z_stream()
    let status = inflateInit2_(&stream, 16 + MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
    guard status == Z_OK else { return nil }
    defer { inflateEnd(&stream) }

    var decompressed = Data()
    let bufferSize = 65536
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    var inflateStatus: Int32 = Z_OK
    data.withUnsafeBytes { rawPtr in
        guard let base = rawPtr.bindMemory(to: Bytef.self).baseAddress else { return }
        stream.next_in = UnsafeMutablePointer<Bytef>(mutating: base)
        stream.avail_in = uInt(data.count)

        repeat {
            stream.next_out = buffer
            stream.avail_out = uInt(bufferSize)
            inflateStatus = inflate(&stream, Z_NO_FLUSH)
            if inflateStatus != Z_OK && inflateStatus != Z_STREAM_END && inflateStatus != Z_BUF_ERROR {
                break
            }
            let decompressedBytes = bufferSize - Int(stream.avail_out)
            if decompressedBytes > 0 {
                decompressed.append(buffer, count: decompressedBytes)
            }
        } while inflateStatus == Z_OK
    }

    return inflateStatus == Z_STREAM_END ? decompressed : nil
}

struct XUpdaterConfig: Sendable {
    var name: String
    var version: String?
    var snapshotNum: Int?
    var remoteURL: String?
    var login: String?
    var licenseKey: String?
    var productId: String?
    var releaseType: String = "release"
    var betaEnabled: Bool = false
}

enum XUpdaterFileState: Int, Codable, Sendable {
    case none = 0
    case add = 1
    case update = 2
    case delete = 3
}

struct XUpdaterFileItem: Codable, Sendable {
    let path: String
    let url: String?
    let md5: String?
    let version: String?
    let state: XUpdaterFileState
    let size: Int64?
    let compressedSize: Int64?
}

final class XUpdaterService: Sendable {
    static let shared = XUpdaterService()
    private var fileManager: FileManager { .default }

    static let defaultXUpdaterHost = "https://update.x-plane.org"

    private let nativeSubdirectories = ["", ".xupdater", ".x-updater", ".x_updater", "x-updater", "x_updater", "xupdater", "data"]

    private let xUpdaterConfigFiles = [
        "settings.ini", "settings.cfg",
        "x-updater.cnf", "x_updater.cnf", "xupdater.cnf",
        "x-updater.cfg", "x_updater.cfg", "xupdater.cfg",
        ".x-updater.cfg", ".x_updater.cfg",
        "x-updater.conf", "x_updater.conf",
        "x-jet-updater.cfg", "xjetupdater.cfg",
        "x-updater.json", "x_updater.json", "xupdater.json",
        ".x-updater.json", ".x_updater.json",
        "x-updater-profile.json", "x_updater_profile.json", "xupdater_profile.json",
        "client-configuration", "productid", "productId", "xupdignore", "description.txt"
    ]

    func findConfig(in folderURL: URL) -> URL? {
        for sub in nativeSubdirectories {
            let searchDir = sub.isEmpty ? folderURL : folderURL.appendingPathComponent(sub)
            for name in xUpdaterConfigFiles {
                let fileURL = searchDir.appendingPathComponent(name)
                if fileManager.fileExists(atPath: fileURL.path) {
                    return fileURL
                }
            }
        }
        return nil
    }

    private func formatVersionString(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count == 6, trimmed.allSatisfy(\.isNumber),
           let major = Int(trimmed.prefix(2)),
           let minor = Int(trimmed.dropFirst(2).prefix(2)),
           let patch = Int(trimmed.suffix(2)) {
            return "\(major).\(minor).\(patch)"
        }
        return trimmed
    }

    func parseConfig(at url: URL, defaultName: String) -> XUpdaterConfig? {
        let parentDir = url.deletingLastPathComponent()
        let addonDir = parentDir.lastPathComponent.hasPrefix(".") || parentDir.lastPathComponent.contains("updater") ? parentDir.deletingLastPathComponent() : parentDir

        var name = defaultName
        var version: String? = nil
        var snapshotNum: Int? = nil
        var remoteURL: String? = nil
        var login: String? = nil
        var licenseKey: String? = nil
        var productId: String? = nil
        var releaseType = "release"
        var betaEnabled = false

        let searchDirs = [parentDir, addonDir, addonDir.appendingPathComponent(".xupdater"), addonDir.appendingPathComponent("x-updater")]
        let candidateFiles = [
            url.lastPathComponent,
            "settings.ini", "settings.cfg",
            "x-updater.cnf", "x_updater.cnf", "xupdater.cnf",
            "x-updater.cfg", "x_updater.cfg", "xupdater.cfg",
            "x-updater.json", "x_updater.json",
            "client-configuration"
        ]

        for dir in searchDirs {
            for fileName in candidateFiles {
                let fileURL = dir.appendingPathComponent(fileName)
                guard fileManager.fileExists(atPath: fileURL.path),
                      let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

                if fileName.hasSuffix(".json"),
                   let data = content.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if name == defaultName, let n = json["name"] as? String ?? json["product_name"] as? String { name = n }
                    if let sNum = json["snapshot_num"] as? Int ?? (json["snapshot"] as? Int) ?? (json["number"] as? Int) {
                        snapshotNum = sNum
                    }
                    if version == nil, let v = json["version"] as? String ?? json["shortDesc"] as? String {
                        version = formatVersionString(v)
                    }
                    if remoteURL == nil, let u = json["update_url"] as? String ?? json["server_url"] as? String { remoteURL = u }
                    if login == nil, let l = json["login"] as? String ?? json["user_name"] as? String { login = l }
                    if licenseKey == nil, let k = json["license_key"] as? String ?? json["user_password"] as? String { licenseKey = k }
                    if productId == nil, let p = json["product_id"] as? String ?? json["productid"] as? String { productId = p }
                    continue
                }

                let lines = content.components(separatedBy: .newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty || trimmed.hasPrefix(";") || trimmed.hasPrefix("#") { continue }
                    let parts = trimmed.components(separatedBy: "=")
                    if parts.count >= 2 {
                        let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
                        let val = parts[1].trimmingCharacters(in: .whitespaces)
                        if (key == "product_name" || key == "name" || key == "product") && name == defaultName {
                            name = val
                        } else if key == "snapshot_num" || key == "snapshot" {
                            if let sNum = Int(val) {
                                snapshotNum = sNum
                            }
                        } else if (key == "version" || key == "product_version" || key == "build") && version == nil {
                            version = formatVersionString(val)
                        } else if (key == "update_url" || key == "server_url" || key == "url" || key == "host") && remoteURL == nil {
                            remoteURL = val
                        } else if (key == "user_name" || key == "login" || key == "email") && login == nil {
                            login = val
                        } else if (key == "user_password" || key == "license_key" || key == "password" || key == "key") && licenseKey == nil {
                            licenseKey = val
                        } else if (key == "productid" || key == "product_id") && productId == nil {
                            productId = val
                        } else if key == "preferred_release_type" || key == "actual_release_type" {
                            releaseType = val.lowercased()
                            betaEnabled = (releaseType == "beta")
                        } else if key == "beta_enabled" || key == "betaenabled" {
                            betaEnabled = (val.lowercased() == "true" || val == "1")
                            if betaEnabled { releaseType = "beta" }
                        }
                    }
                }
            }
        }

        if productId == nil {
            for dir in searchDirs {
                for idName in ["productId", "productid"] {
                    let idURL = dir.appendingPathComponent(idName)
                    if let raw = try? String(contentsOf: idURL, encoding: .utf8) {
                        let idContent = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !idContent.isEmpty {
                            productId = idContent
                            break
                        }
                    }
                }
                if productId != nil { break }
            }
        }

        // Try reading version from release-notes.txt or version-*.txt
        if version == nil {
            for dir in searchDirs {
                let notesURL = dir.appendingPathComponent("release-notes.txt")
                if let notesContent = try? String(contentsOf: notesURL, encoding: .utf8) {
                    for line in notesContent.components(separatedBy: .newlines) {
                        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !t.isEmpty && !t.hasPrefix("#") && !t.hasPrefix(";") && !t.hasPrefix("-") && (t.first?.isNumber == true || t.hasPrefix("v")) {
                            version = t
                            break
                        }
                    }
                }
                if version != nil { break }
            }
        }

        if version == nil {
            if let contents = try? fileManager.contentsOfDirectory(at: addonDir, includingPropertiesForKeys: nil) {
                for item in contents {
                    if item.lastPathComponent.hasPrefix("version-") && item.pathExtension == "txt" {
                        if let raw = try? String(contentsOf: item, encoding: .utf8) {
                            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !t.isEmpty {
                                version = formatVersionString(t)
                                break
                            }
                        }
                    }
                }
            }
        }

        if version == nil, let sNum = snapshotNum {
            version = "snapshot \(sNum)"
        }

        if remoteURL == nil || remoteURL?.isEmpty == true {
            remoteURL = Self.defaultXUpdaterHost
        }

        return XUpdaterConfig(
            name: name,
            version: version,
            snapshotNum: snapshotNum,
            remoteURL: remoteURL,
            login: login,
            licenseKey: licenseKey,
            productId: productId,
            releaseType: releaseType,
            betaEnabled: betaEnabled
        )
    }

    func authenticate(
        host: String,
        login: String,
        licenseKey: String,
        logHandler: @Sendable @escaping (String) -> Void = { _ in }
    ) async -> String? {
        var base = host.trimmingCharacters(in: .whitespaces)
        if !base.hasPrefix("http://") && !base.hasPrefix("https://") {
            base = "https://" + base
        }
        if base.hasSuffix("/") {
            base.removeLast()
        }
        let authURLString = base + "/api/v2/service/auth/consumers"
        guard let authURL = URL(string: authURLString) else { return nil }

        logHandler("[X-Updater] Authenticating with server \(authURL.host ?? "") for user \(login)...")

        var request = URLRequest(url: authURL)
        request.httpMethod = "POST"
        request.setValue("X-Updater-Java-Client/2.0", forHTTPHeaderField: "User-Agent")
        request.setValue("macOS", forHTTPHeaderField: "XUpdater-OS")
        request.setValue("1.8.0", forHTTPHeaderField: "XUpdater-Java")

        let credentialsString = "\(login):\(licenseKey)"
        if let credData = credentialsString.data(using: .utf8) {
            let base64Creds = credData.base64EncodedString()
            request.setValue("Basic \(base64Creds)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            logHandler("[X-Updater] Auth HTTP Response \(statusCode) (\(data.count) bytes)")

            if statusCode == 200, let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
                logHandler("[X-Updater] Successfully authenticated with X-Updater server.")
                return token
            }
        } catch {
            logHandler("[X-Updater] Authentication request error: \(error.localizedDescription)")
        }

        return nil
    }

    func fetchFileList(
        filesURLString: String,
        since: Int? = nil,
        token: String,
        logHandler: @Sendable @escaping (String) -> Void = { _ in }
    ) async throws -> [XUpdaterFileItem] {
        var fullURLString = filesURLString
        if !fullURLString.hasPrefix("http://") && !fullURLString.hasPrefix("https://") {
            fullURLString = "https://" + fullURLString
        }
        if let s = since {
            let separator = fullURLString.contains("?") ? "&" : "?"
            fullURLString += "\(separator)since=\(s)"
        }

        guard let url = URL(string: fullURLString) else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("X-Updater-Java-Client/2.0", forHTTPHeaderField: "User-Agent")
        request.setValue("macOS", forHTTPHeaderField: "XUpdater-OS")
        request.setValue("1.8.0", forHTTPHeaderField: "XUpdater-Java")
        request.setValue(token, forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        logHandler("[X-Updater] File list HTTP Response \(statusCode) (\(data.count) bytes)")

        guard statusCode == 200,
              let jsonArray = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return []
        }

        var items: [XUpdaterFileItem] = []
        for fileObj in jsonArray {
            guard let location = fileObj["location"] as? String else { continue }
            let hash = fileObj["hash"] as? String
            let rawState = fileObj["state"] as? Int ?? 0
            let state = XUpdaterFileState(rawValue: rawState) ?? .none
            let size = (fileObj["size"] as? NSNumber)?.int64Value
            let compressedSize = (fileObj["compressedSize"] as? NSNumber)?.int64Value

            var downloadURL: String? = nil
            if let links = fileObj["_links"] as? [String: Any],
               let dataLink = links["xu:data"] as? [String: Any],
               let href = dataLink["href"] as? String {
                downloadURL = href.hasPrefix("http") ? href : "https://" + href
            }
            items.append(XUpdaterFileItem(
                path: location,
                url: downloadURL,
                md5: hash,
                version: nil,
                state: state,
                size: size,
                compressedSize: compressedSize
            ))
        }

        logHandler("[X-Updater] Received \(items.count) files in update manifest.")
        return items
    }

    func checkRemoteVersion(
        config: XUpdaterConfig,
        logHandler: @Sendable @escaping (String) -> Void = { _ in }
    ) async throws -> (version: String?, snapshotNum: Int?, files: [XUpdaterFileItem]) {
        let host = config.remoteURL ?? Self.defaultXUpdaterHost

        var authToken: String? = nil
        if let login = config.login, let key = config.licenseKey, !login.isEmpty, !key.isEmpty {
            authToken = await authenticate(host: host, login: login, licenseKey: key, logHandler: logHandler)
        }

        guard let token = authToken else {
            logHandler("[X-Updater] Could not acquire authentication token for \(config.name)")
            return (nil, nil, [])
        }

        var updatesURLString = host
        if !updatesURLString.hasPrefix("http://") && !updatesURLString.hasPrefix("https://") {
            updatesURLString = "https://" + updatesURLString
        }
        if updatesURLString.hasSuffix("/") {
            updatesURLString.removeLast()
        }
        updatesURLString += "/api/v2/experimental/updates"

        guard let updatesURL = URL(string: updatesURLString) else {
            throw URLError(.badURL)
        }

        logHandler("[X-Updater] Querying product updates from \(updatesURL.absoluteString)...")
        var request = URLRequest(url: updatesURL)
        request.httpMethod = "GET"
        request.setValue("X-Updater-Java-Client/2.0", forHTTPHeaderField: "User-Agent")
        request.setValue("macOS", forHTTPHeaderField: "XUpdater-OS")
        request.setValue("1.8.0", forHTTPHeaderField: "XUpdater-Java")
        request.setValue(token, forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        logHandler("[X-Updater] Updates API HTTP Response \(statusCode) (\(data.count) bytes)")

        guard statusCode == 200 else {
            logHandler("[X-Updater] Updates API returned non-200 status: \(statusCode)")
            return (nil, nil, [])
        }

        var productList: [[String: Any]] = []
        if let jsonArray = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
            productList = jsonArray
        } else if let jsonDict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            if let products = jsonDict["products"] as? [[String: Any]] {
                productList = products
            } else if let dataArray = jsonDict["data"] as? [[String: Any]] {
                productList = dataArray
            } else if let items = jsonDict["items"] as? [[String: Any]] {
                productList = items
            }
        }

        guard !productList.isEmpty else {
            logHandler("[X-Updater] Failed to parse product updates JSON")
            return (nil, nil, [])
        }

        // Find matching product
        var matchedProduct: [String: Any]? = nil
        if let targetId = config.productId?.lowercased(), !targetId.isEmpty {
            matchedProduct = productList.first(where: { ($0["id"] as? String)?.lowercased() == targetId })
        }
        if matchedProduct == nil {
            let targetNameLower = config.name.lowercased()
            matchedProduct = productList.first(where: {
                guard let pName = ($0["name"] as? String)?.lowercased() else { return false }
                return pName.contains(targetNameLower) || targetNameLower.contains(pName)
            })
        }
        if matchedProduct == nil {
            matchedProduct = productList.first
        }

        guard let product = matchedProduct else {
            logHandler("[X-Updater] No matching product found in account.")
            return (nil, nil, [])
        }

        let productName = product["name"] as? String ?? config.name
        logHandler("[X-Updater] Matched remote product: '\(productName)' (ID: \(product["id"] as? String ?? "unknown"))")

        var latestVersion: String? = nil
        var remoteSnapshotNum: Int? = nil
        var filesURLString: String? = nil

        if let snapshots = product["snapshots"] as? [[String: Any]], !snapshots.isEmpty {
            let targetType = config.betaEnabled ? "beta" : "release"
            let filteredSnapshots = snapshots.filter { ($0["type"] as? String)?.lowercased() == targetType }
            let selectedSnapshot = filteredSnapshots.last ?? snapshots.last

            if let snap = selectedSnapshot {
                if let num = snap["number"] as? Int ?? (snap["snapshot"] as? Int) ?? (snap["snapshot_num"] as? Int) {
                    remoteSnapshotNum = num
                }
                if let shortDesc = snap["shortDesc"] as? String, !shortDesc.isEmpty {
                    latestVersion = formatVersionString(shortDesc)
                } else if let num = remoteSnapshotNum {
                    latestVersion = "snapshot \(num)"
                }

                if let links = snap["_links"] as? [String: Any],
                   let filesLink = links["xu:files"] as? [String: Any],
                   let href = filesLink["href"] as? String {
                    filesURLString = href
                }
            }
        }

        if filesURLString == nil,
           let links = product["_links"] as? [String: Any],
           let filesLink = links["xu:files"] as? [String: Any],
           let href = filesLink["href"] as? String {
            filesURLString = href
        }

        if latestVersion == nil {
            if let ver = product["version"] as? String {
                latestVersion = formatVersionString(ver)
            } else if let sNum = remoteSnapshotNum {
                latestVersion = "snapshot \(sNum)"
            }
        }

        logHandler("[X-Updater] Detected remote version: \(latestVersion ?? "unknown") (Snapshot: \(remoteSnapshotNum.map(String.init) ?? "none"))")

        guard let filesHref = filesURLString else {
            return (latestVersion, remoteSnapshotNum, [])
        }

        let files = try await fetchFileList(
            filesURLString: filesHref,
            since: config.snapshotNum,
            token: token,
            logHandler: logHandler
        )
        return (latestVersion, remoteSnapshotNum, files)
    }

    private func computeMD5(of fileURL: URL) -> String? {
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { return nil }
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    func resolveLocalFile(itemPath: String, in folderURL: URL) -> (exists: Bool, actualURL: URL?) {
        let directURL = folderURL.appendingPathComponent(itemPath)
        if fileManager.fileExists(atPath: directURL.path) {
            return (true, directURL)
        }

        let pathLower = itemPath.lowercased()

        // Check DDS <-> PNG equivalence with case-insensitivity in parent directory
        if pathLower.hasSuffix(".png") || pathLower.hasSuffix(".dds") {
            let isPng = pathLower.hasSuffix(".png")
            let altExt = isPng ? ".dds" : ".png"
            let stem = (itemPath as NSString).deletingPathExtension
            let altPath = stem + altExt
            let altURL = folderURL.appendingPathComponent(altPath)
            if fileManager.fileExists(atPath: altURL.path) {
                return (true, altURL)
            }

            let parentDir = altURL.deletingLastPathComponent()
            let altTargetName = altURL.lastPathComponent.lowercased()
            if let contents = try? fileManager.contentsOfDirectory(atPath: parentDir.path) {
                if let match = contents.first(where: { $0.lowercased() == altTargetName }) {
                    return (true, parentDir.appendingPathComponent(match))
                }
            }
        }

        // Check general case-insensitive match for the direct file in parent dir
        let parentDir = directURL.deletingLastPathComponent()
        let directTargetName = directURL.lastPathComponent.lowercased()
        if let contents = try? fileManager.contentsOfDirectory(atPath: parentDir.path) {
            if let match = contents.first(where: { $0.lowercased() == directTargetName }) {
                return (true, parentDir.appendingPathComponent(match))
            }
        }

        // Check alt subfolder path (e.g., stem/stem/file)
        let lastComponent = (itemPath as NSString).lastPathComponent
        let stem = (lastComponent as NSString).deletingPathExtension
        let parentPath = (itemPath as NSString).deletingLastPathComponent
        let altSubPath = parentPath.isEmpty ? "\(stem)/\(lastComponent)" : "\(parentPath)/\(stem)/\(lastComponent)"
        let subURL = folderURL.appendingPathComponent(altSubPath)
        if fileManager.fileExists(atPath: subURL.path) {
            return (true, subURL)
        }

        return (false, nil)
    }

    func checkAddonStatus(
        folderURL: URL,
        config: XUpdaterConfig,
        logHandler: @Sendable @escaping (String) -> Void = { _ in }
    ) async throws -> (latestVersion: String?, isUpdateAvailable: Bool, statusMessage: String) {
        var activeConfig = config
        if (activeConfig.login == nil || activeConfig.licenseKey == nil || activeConfig.snapshotNum == nil),
           let configFile = findConfig(in: folderURL),
           let fullConfig = parseConfig(at: configFile, defaultName: config.name) {
            activeConfig = fullConfig
        }

        logHandler("[X-Updater] Checking '\(activeConfig.name)' (Local: \(activeConfig.version ?? "none"), Snapshot: \(activeConfig.snapshotNum.map(String.init) ?? "none"))")
        if let user = activeConfig.login {
            logHandler("[X-Updater] User: \(user)")
        } else {
            logHandler("[X-Updater] Warning: No user credentials found for \(activeConfig.name)")
        }

        do {
            let (remoteVersion, remoteSnapshotNum, files) = try await checkRemoteVersion(config: activeConfig, logHandler: logHandler)
            let latestVersion = remoteVersion ?? activeConfig.version

            if files.isEmpty && remoteVersion == nil {
                logHandler("[X-Updater] No remote manifest returned; assuming \(activeConfig.name) is up to date.")
                return (activeConfig.version, false, "Up to date")
            }

            var modifiedCount = 0
            var missingCount = 0
            var deleteCount = 0

            for item in files {
                let localFileURL = folderURL.appendingPathComponent(item.path)

                if item.state == .delete {
                    // For files marked to be deleted: only count if currently present locally
                    if fileManager.fileExists(atPath: localFileURL.path) {
                        deleteCount += 1
                        logHandler("[X-Updater] Deprecated file to delete: \(item.path)")
                    }
                    continue
                }

                let (exists, actualURL) = resolveLocalFile(itemPath: item.path, in: folderURL)

                if exists, let fileURL = actualURL {
                    let isDDSConversion = fileURL.pathExtension.lowercased() == "dds" && (item.path as NSString).pathExtension.lowercased() == "png"
                    if !isDDSConversion, let remoteMD5 = item.md5?.lowercased(), !remoteMD5.isEmpty {
                        if let localMD5 = computeMD5(of: fileURL)?.lowercased(), localMD5 != remoteMD5 {
                            modifiedCount += 1
                            logHandler("[X-Updater] Modified file: \(item.path) (local: \(localMD5), remote: \(remoteMD5))")
                        }
                    }
                } else if item.size == 0 && item.path.contains("marker") {
                    // Ignore 0-byte runtime markers if absent
                    continue
                } else {
                    missingCount += 1
                    logHandler("[X-Updater] Missing file: \(item.path)")
                }
            }

            let totalChanges = modifiedCount + missingCount + deleteCount
            let snapshotMismatch = (remoteSnapshotNum != nil && activeConfig.snapshotNum != nil && remoteSnapshotNum! > activeConfig.snapshotNum!)
            let isUpdateAvailable = snapshotMismatch || (totalChanges > 0)

            var statusMessage = "Up to date"
            if isUpdateAvailable {
                if let rVersion = remoteVersion, rVersion != activeConfig.version {
                    if totalChanges > 0 {
                        statusMessage = "Update available (\(rVersion) - \(totalChanges) files)"
                    } else {
                        statusMessage = "Update available (\(rVersion))"
                    }
                    logHandler("[X-Updater] Update available: Local '\(activeConfig.version ?? "none")' vs Remote '\(rVersion)'")
                } else if totalChanges > 0 {
                    if missingCount > 0 && modifiedCount == 0 {
                        statusMessage = "Needs repair (\(missingCount) missing file\(missingCount > 1 ? "s" : ""))"
                    } else if modifiedCount > 0 && missingCount == 0 {
                        statusMessage = "Needs repair (\(modifiedCount) modified file\(modifiedCount > 1 ? "s" : ""))"
                    } else {
                        statusMessage = "Needs repair (\(totalChanges) changed files)"
                    }
                    logHandler("[X-Updater] \(totalChanges) files modified, missing, or deprecated locally")
                } else {
                    statusMessage = "Update available"
                }
            } else {
                logHandler("[X-Updater] \(activeConfig.name) is up to date.")
            }

            return (latestVersion, isUpdateAvailable, statusMessage)
        } catch {
            logHandler("[X-Updater] Error checking remote endpoint for \(activeConfig.name): \(error.localizedDescription)")
            return (activeConfig.version, false, "Check failed")
        }
    }

    func downloadAndApplyUpdates(
        for addonFolder: URL,
        config: XUpdaterConfig,
        logHandler: @Sendable @escaping (String) -> Void = { _ in },
        progressHandler: @Sendable @escaping (String, Double) -> Void
    ) async throws {
        var activeConfig = config
        if (activeConfig.login == nil || activeConfig.licenseKey == nil || activeConfig.snapshotNum == nil),
           let configFile = findConfig(in: addonFolder),
           let fullConfig = parseConfig(at: configFile, defaultName: config.name) {
            activeConfig = fullConfig
        }

        logHandler("[X-Updater] Starting update / repair for \(activeConfig.name)...")
        let (remoteVersion, remoteSnapshotNum, files) = try await checkRemoteVersion(config: activeConfig, logHandler: logHandler)

        if files.isEmpty {
            logHandler("[X-Updater] No files returned in manifest.")
            progressHandler("Up to date", 1.0)
            return
        }

        // Filter files needing download or deletion
        var filesToDownload: [XUpdaterFileItem] = []
        var filesToDelete: [XUpdaterFileItem] = []

        for item in files {
            let (exists, actualURL) = resolveLocalFile(itemPath: item.path, in: addonFolder)

            if item.state == .delete {
                if exists {
                    filesToDelete.append(item)
                }
                continue
            }

            if !exists {
                if item.size == 0 && item.path.contains("marker") { continue }
                filesToDownload.append(item)
            } else if let fileURL = actualURL {
                let isDDSConversion = fileURL.pathExtension.lowercased() == "dds" && (item.path as NSString).pathExtension.lowercased() == "png"
                if !isDDSConversion, let remoteMD5 = item.md5?.lowercased(), !remoteMD5.isEmpty {
                    if let localMD5 = computeMD5(of: fileURL)?.lowercased(), localMD5 != remoteMD5 {
                        filesToDownload.append(item)
                    }
                }
            }
        }

        let totalActions = filesToDelete.count + filesToDownload.count
        if totalActions == 0 {
            logHandler("[X-Updater] All files match expected hashes. Addon is already intact.")
            progressHandler("Up to date", 1.0)
            return
        }

        logHandler("[X-Updater] Processing \(totalActions) files (\(filesToDownload.count) to download, \(filesToDelete.count) to remove)...")
        var currentAction = 0

        for item in filesToDelete {
            currentAction += 1
            let progress = Double(currentAction) / Double(totalActions)
            progressHandler("Removing (\(currentAction)/\(totalActions)): \(item.path)", progress)
            let destinationURL = addonFolder.appendingPathComponent(item.path)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try? fileManager.removeItem(at: destinationURL)
                logHandler("[X-Updater] Removed deprecated file \(item.path)")
            }
        }

        for item in filesToDownload {
            currentAction += 1
            let progress = Double(currentAction) / Double(totalActions)
            progressHandler("Downloading (\(currentAction)/\(totalActions)): \(item.path)", progress)

            guard let downloadURLString = item.url ?? activeConfig.remoteURL,
                  let downloadURL = URL(string: downloadURLString) else { continue }

            logHandler("[X-Updater] Fetching \(downloadURL.absoluteString)...")
            let (fileData, response) = try await URLSession.shared.data(from: downloadURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                logHandler("[X-Updater] Failed download for \(item.path) (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))")
                continue
            }

            let destinationURL = addonFolder.appendingPathComponent(item.path)
            let parentDir = destinationURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)

            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            let finalData = decompressGzip(data: fileData) ?? fileData
            try finalData.write(to: destinationURL, options: Data.WritingOptions.atomic)
            logHandler("[X-Updater] Repaired/Updated \(item.path) (\(finalData.count) bytes)")
        }

        // Update snapshot_num in local settings.ini if available
        if let newSnapshot = remoteSnapshotNum {
            updateLocalSettings(in: addonFolder, newSnapshotNum: newSnapshot, newVersion: remoteVersion)
        }

        logHandler("[X-Updater] Update / Repair completed successfully.")
        progressHandler("Up to date", 1.0)
    }

    private func updateLocalSettings(in addonFolder: URL, newSnapshotNum: Int, newVersion: String?) {
        let candidatePaths = [
            addonFolder.appendingPathComponent(".xupdater/settings.ini"),
            addonFolder.appendingPathComponent("x-updater/settings.ini"),
            addonFolder.appendingPathComponent("settings.ini")
        ]

        for settingsURL in candidatePaths {
            guard fileManager.fileExists(atPath: settingsURL.path),
                  let content = try? String(contentsOf: settingsURL, encoding: .utf8) else { continue }

            var lines = content.components(separatedBy: .newlines)
            var foundSnapshot = false
            var foundUpdatedAt = false
            let nowTimestamp = Int(Date().timeIntervalSince1970)

            for (idx, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("snapshot_num=") {
                    lines[idx] = "snapshot_num=\(newSnapshotNum)"
                    foundSnapshot = true
                } else if trimmed.hasPrefix("updated_at=") {
                    lines[idx] = "updated_at=\(nowTimestamp)"
                    foundUpdatedAt = true
                }
            }

            if !foundSnapshot {
                lines.append("snapshot_num=\(newSnapshotNum)")
            }
            if !foundUpdatedAt {
                lines.append("updated_at=\(nowTimestamp)")
            }

            let updatedContent = lines.joined(separator: "\n")
            try? updatedContent.write(to: settingsURL, atomically: true, encoding: .utf8)
            break
        }
    }
}
