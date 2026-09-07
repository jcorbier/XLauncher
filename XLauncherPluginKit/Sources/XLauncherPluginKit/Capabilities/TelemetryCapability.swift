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

import CoreLocation
import Foundation

public struct FlightTelemetrySnapshot: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let altitudeMslMeters: Double
    public let altitudeAglMeters: Double
    public let indicatedAirspeedKts: Double
    public let groundSpeedKts: Double
    public let verticalSpeedFpm: Double
    public let pitchDegrees: Double
    public let bankDegrees: Double
    public let headingTrueDegrees: Double
    public let normalGForce: Double
    public let isOnGround: Bool
    public let parkingBrakeRatio: Double
    public let currentPhase: String
    public let isPaused: Bool

    public init(
        latitude: Double = 0,
        longitude: Double = 0,
        altitudeMslMeters: Double = 0,
        altitudeAglMeters: Double = 0,
        indicatedAirspeedKts: Double = 0,
        groundSpeedKts: Double = 0,
        verticalSpeedFpm: Double = 0,
        pitchDegrees: Double = 0,
        bankDegrees: Double = 0,
        headingTrueDegrees: Double = 0,
        normalGForce: Double = 1.0,
        isOnGround: Bool = true,
        parkingBrakeRatio: Double = 1.0,
        currentPhase: String = "Parked",
        isPaused: Bool = false
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitudeMslMeters = altitudeMslMeters
        self.altitudeAglMeters = altitudeAglMeters
        self.indicatedAirspeedKts = indicatedAirspeedKts
        self.groundSpeedKts = groundSpeedKts
        self.verticalSpeedFpm = verticalSpeedFpm
        self.pitchDegrees = pitchDegrees
        self.bankDegrees = bankDegrees
        self.headingTrueDegrees = headingTrueDegrees
        self.normalGForce = normalGForce
        self.isOnGround = isOnGround
        self.parkingBrakeRatio = parkingBrakeRatio
        self.currentPhase = currentPhase
        self.isPaused = isPaused
    }
}

public protocol TelemetryProvider: Sendable {
    /// Starts real-time telemetry tracking from simulator host and port
    func startTracking(host: String, port: Int) async throws

    /// Stops tracking
    func stopTracking()

    /// Current telemetry snapshot
    func currentSnapshot() -> FlightTelemetrySnapshot?

    /// Continuous async stream of telemetry updates
    func telemetryStream() -> AsyncStream<FlightTelemetrySnapshot>

    /// Recorded coordinates of current flight session breadcrumb trail
    func flightTrail() -> [CLLocationCoordinate2D]
}

public extension TelemetryProvider {
    func flightTrail() -> [CLLocationCoordinate2D] { [] }
}
