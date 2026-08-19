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

import AppKit
import Foundation
import Observation

public struct NavigraphUser: Codable, Equatable, Hashable, Sendable {
    public let userId: Int
    public let username: String
    public let firstName: String?
    public let lastName: String?
    public let preferredRegion: String?

    public init(
        userId: Int,
        username: String,
        firstName: String? = nil,
        lastName: String? = nil,
        preferredRegion: String? = "EUC1"
    ) {
        self.userId = userId
        self.username = username
        self.firstName = firstName
        self.lastName = lastName
        self.preferredRegion = preferredRegion
    }

    public var displayName: String {
        if let first = firstName, !first.isEmpty, let last = lastName, !last.isEmpty {
            return "\(first) \(last)"
        }
        return username
    }
}

@MainActor
@Observable
public final class NavigraphAuthManager {

    public enum AuthState: Equatable {
        case unauthenticated
        case authenticating
        case authenticated(user: NavigraphUser)
        case error(String)
    }

    public var authState: AuthState = .unauthenticated
    public private(set) var token: String?
    public private(set) var currentUser: NavigraphUser?

    private struct SavedSession: Codable {
        let token: String
        let user: NavigraphUser?
    }

    public init() {
        if let session = loadSavedSession(), !session.token.isEmpty {
            self.token = session.token
            let cachedUser = session.user ?? NavigraphUser(userId: 0, username: "Navigraph User")
            self.currentUser = cachedUser
            self.authState = .authenticated(user: cachedUser)
        }
    }

    public var savedEmail: String {
        get { UserDefaults.standard.string(forKey: .navigraphSavedEmail) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: .navigraphSavedEmail) }
    }

    // MARK: - Session Restoration

    /// Restores the authenticated state from UserDefaults.
    public func restoreSessionOnLaunch() async {
        if let session = loadSavedSession(), !session.token.isEmpty {
            self.token = session.token
            let cachedUser = session.user ?? NavigraphUser(userId: 0, username: "Navigraph User")
            self.currentUser = cachedUser
            self.authState = .authenticated(user: cachedUser)
        } else {
            self.authState = .unauthenticated
        }
    }

    // MARK: - OTP Authentication

    /// Authenticates with Navigraph using username/email and a One-Time Password generated at https://navigraph.com/account/otp
    public func authenticate(email: String, otp: String) async throws {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOTP = otp.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        guard !trimmedEmail.isEmpty else {
            throw NSError(domain: "NavigraphAuth", code: 400, userInfo: [NSLocalizedDescriptionKey: "Email address cannot be empty."])
        }

        guard !trimmedOTP.isEmpty else {
            throw NSError(domain: "NavigraphAuth", code: 400, userInfo: [NSLocalizedDescriptionKey: "One-Time Password (OTP) cannot be empty."])
        }

        self.savedEmail = trimmedEmail
        self.authState = .authenticating

        let tokenURL = URL(string: "https://www.navigraph.com/api/1/token?grant_type=password")!
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let payload: [String: String] = [
            "client_identifier": "fms-client",
            "username": trimmedEmail,
            "user_password": trimmedOTP
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            let err = "Invalid network response from Navigraph."
            self.authState = .error(err)
            throw NSError(domain: "NavigraphAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: err])
        }

        guard httpResponse.statusCode == 200 else {
            let errorMsg: String
            if let errorObj = try? JSONDecoder().decode(FMSErrorResponse.self, from: data), let desc = errorObj.Message {
                errorMsg = desc
            } else if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
                errorMsg = raw
            } else {
                errorMsg = "Authentication failed (HTTP \(httpResponse.statusCode)). Please check your OTP."
            }

            self.authState = .error(errorMsg)
            throw NSError(domain: "NavigraphAuth", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        let authResponse = try JSONDecoder().decode(FMSTokenResponse.self, from: data)
        let user = NavigraphUser(
            userId: authResponse.user.user_id,
            username: authResponse.user.username,
            firstName: authResponse.user.first_name,
            lastName: authResponse.user.last_name,
            preferredRegion: authResponse.user.preferred_region
        )

        self.token = authResponse.token
        self.currentUser = user
        self.authState = .authenticated(user: user)

        saveSession(token: authResponse.token, user: user)

        ConsoleLogger.shared.log("Navigraph FMS login successful for user '\(user.displayName)'.", category: .navdata)
    }

    public func signOut() {
        deleteSavedSession()
        self.token = nil
        self.currentUser = nil
        self.authState = .unauthenticated
        ConsoleLogger.shared.log("Navigraph user signed out.", category: .navdata)
    }

    // MARK: - UserDefaults Session Storage

    private func saveSession(token: String, user: NavigraphUser?) {
        let session = SavedSession(token: token, user: user)
        guard let data = try? JSONEncoder().encode(session) else { return }
        UserDefaults.standard.set(data, forKey: .navigraphSession)
        ConsoleLogger.shared.log("Saved Navigraph session for '\(user?.displayName ?? "User")'.", category: .navdata)
    }

    private func loadSavedSession() -> SavedSession? {
        guard let data = UserDefaults.standard.data(forKey: .navigraphSession),
              let session = try? JSONDecoder().decode(SavedSession.self, from: data) else {
            return nil
        }
        return session
    }

    private func deleteSavedSession() {
        UserDefaults.standard.removeObject(forKey: .navigraphSession)
        ConsoleLogger.shared.log("Deleted Navigraph session.", category: .navdata)
    }
}

// MARK: - Internal DTOs

private struct FMSTokenResponse: Codable {
    let token: String
    let client_identifier: String
    let user: FMSUserDTO
    let token_expiry: String?
}

private struct FMSUserDTO: Codable {
    let user_id: Int
    let username: String
    let first_name: String?
    let last_name: String?
    let preferred_region: String?
}

private struct FMSErrorResponse: Codable {
    let Message: String?
    let error: String?
}
