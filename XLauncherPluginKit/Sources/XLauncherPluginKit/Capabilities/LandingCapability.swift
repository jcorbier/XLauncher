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

public struct LandingReport: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let verticalSpeedFpm: Double
    public let normalGForce: Double
    public let pitchDegrees: Double
    public let bankDegrees: Double
    public let groundSpeedKts: Double
    public let latitude: Double
    public let longitude: Double
    public let rating: String

    public init(
        timestamp: Date = Date(),
        verticalSpeedFpm: Double,
        normalGForce: Double,
        pitchDegrees: Double,
        bankDegrees: Double,
        groundSpeedKts: Double,
        latitude: Double,
        longitude: Double,
        rating: String
    ) {
        self.timestamp = timestamp
        self.verticalSpeedFpm = verticalSpeedFpm
        self.normalGForce = normalGForce
        self.pitchDegrees = pitchDegrees
        self.bankDegrees = bankDegrees
        self.groundSpeedKts = groundSpeedKts
        self.latitude = latitude
        self.longitude = longitude
        self.rating = rating
    }
}

public protocol LandingAnalyticsProvider: Sendable {
    var lastReport: LandingReport? { get }
    func landingReportStream() -> AsyncStream<LandingReport>
}
