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

public struct FlightDispatchPlan: Codable, Equatable, Sendable {
    public let departureICAO: String
    public let arrivalICAO: String
    public let aircraftType: String?
    public let rawPayload: [String: String]

    public init(
        departureICAO: String,
        arrivalICAO: String,
        aircraftType: String? = nil,
        rawPayload: [String: String] = [:]
    ) {
        self.departureICAO = departureICAO
        self.arrivalICAO = arrivalICAO
        self.aircraftType = aircraftType
        self.rawPayload = rawPayload
    }
}

public struct FlightDispatchResult: Codable, Equatable, Sendable {
    public let isSuccess: Bool
    public let message: String

    public init(isSuccess: Bool, message: String) {
        self.isSuccess = isSuccess
        self.message = message
    }
}

public protocol FlightDispatchProvider: Sendable {
    func dispatchFlight(_ plan: FlightDispatchPlan) async throws -> FlightDispatchResult
}
