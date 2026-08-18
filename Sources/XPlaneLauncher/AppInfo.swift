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

enum AppInfo {
    static let appName = "X-Plane Launcher"
    static let author = "Jeremie Corbier"
    static let copyright = "Copyright © 2026 Jeremie Corbier"
    static let license = "MIT License"
    
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }
    
    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    }
    
    static var displayVersion: String {
        let ver = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if ver.isEmpty {
            return "Development Build"
        }
        let build = buildNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if !build.isEmpty && build != ver {
            return "Version \(ver) (\(build))"
        }
        return "Version \(ver)"
    }
    
    static let githubURL = URL(string: "https://github.com/jcorbier/XLauncher")!
    static let releasesURL = URL(string: "https://github.com/jcorbier/XLauncher/releases")!
    static let issuesURL = URL(string: "https://github.com/jcorbier/XLauncher/issues")!
    static let authorURL = URL(string: "https://github.com/jcorbier")!
    
    static var documentationURL: URL {
        let ver = version.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If it's a tagged release (not empty and not a dev/draft build)
        if !ver.isEmpty && !ver.contains("draft") && !ver.contains("dev") && ver != "0.0.0" {
            let tag = ver.hasPrefix("v") ? ver : "v\(ver)"
            if let url = URL(string: "https://xlauncher.readthedocs.io/en/\(tag)/") {
                return url
            }
        }
        
        return URL(string: "https://xlauncher.readthedocs.io/en/latest/")!
    }
    
    static let licenseText = """
    Copyright (c) 2026 Jeremie Corbier

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
    """
}
