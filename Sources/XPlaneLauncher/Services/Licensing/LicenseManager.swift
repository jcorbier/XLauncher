//
//  LicenseManager.swift
//  XPlaneLauncher
//
//  Central manager for XLauncher Pro licensing state, in-app Stripe checkout,
//  node-locked activation, and offline persistence.
//

import Foundation
import Observation

extension Notification.Name {
    public static let proLicenseStateChanged = Notification.Name("proLicenseStateChanged")
}

@Observable
public final class LicenseManager: @unchecked Sendable {
    public var isPro: Bool = false
    public var licenseRecord: LicenseRecord? = nil

    public var isActivating: Bool = false
    public var activationError: String? = nil

    public var isStartingTrial: Bool = false
    public var trialError: String? = nil

    public var isCheckingOut: Bool = false
    public var activeCheckoutURL: URL? = nil
    public var activeCheckoutSessionId: String? = nil

    public var isCheckingStatus: Bool = false
    public var productInfo: ProductTierInfo? = nil

    public let proxyBaseURL: URL
    public let productId: String

    private static let hasUsedTrialDefaultsKey = "com.xlauncher.hasUsedTrial"

    public var hasUsedTrial: Bool {
        get {
            UserDefaults.standard.bool(forKey: Self.hasUsedTrialDefaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.hasUsedTrialDefaultsKey)
        }
    }

    public static let shared = LicenseManager()

    public init(
        proxyBaseURL: URL = URL(string: "https://cyberpatate-license.cyberpatate.workers.dev")!,
        productId: String = "xlauncher"
    ) {
        self.proxyBaseURL = proxyBaseURL
        self.productId = productId
    }

    // MARK: - Lifecycle

    /// Restores cached license from Application Support at launch and validates against this machine and Ed25519 signature.
    @MainActor
    public func initialize(skipNetwork: Bool = false) {
        if let cached = LicenseStorage.loadLicense() {
            let currentFingerprint = DeviceFingerprint.getHashedFingerprint()
            var isCryptographicallyValid = true
            var isExpired = false

            // If the cached license is an Ed25519 cryptographic license/key, verify signature
            if KeygenCrypto.isCryptographicLicense(cached.licenseKey) {
                if cached.licenseKey.hasPrefix("key/") {
                    let result = KeygenCrypto.verifySignedKey(cached.licenseKey)
                    isCryptographicallyValid = result.isValid
                    isExpired = result.isExpired
                } else if cached.licenseKey.contains("BEGIN") {
                    let result = KeygenCrypto.verifyLicenseFile(cached.licenseKey)
                    isCryptographicallyValid = result.isValid
                    isExpired = result.isExpired
                }
            }

            if cached.isTrial {
                self.hasUsedTrial = true
            }

            let fingerprintMatches = cached.machineFingerprint.isEmpty || cached.machineFingerprint == currentFingerprint
            let statusMatches = (cached.status == "active" || cached.status == "trial" || cached.status.isEmpty) && cached.status != "expired"

            if isCryptographicallyValid && !isExpired && fingerprintMatches && statusMatches {
                self.isPro = true
                self.licenseRecord = cached
            } else {
                // Fingerprint mismatch, expired certificate, or forged cryptographic signature
                if isExpired || cached.status == "expired" {
                    let expiredRecord = LicenseRecord(
                        licenseKey: cached.licenseKey,
                        licenseId: cached.licenseId,
                        machineFingerprint: cached.machineFingerprint,
                        machineName: cached.machineName,
                        activatedAt: cached.activatedAt,
                        productId: cached.productId,
                        status: "expired"
                    )
                    LicenseStorage.saveLicense(expiredRecord)
                    self.licenseRecord = expiredRecord
                } else if !isCryptographicallyValid {
                    LicenseStorage.deleteLicense()
                    self.licenseRecord = nil
                } else {
                    self.licenseRecord = nil
                }
                self.isPro = false
            }
        }

        guard !skipNetwork else { return }

        Task {
            await fetchProductInfo()
            if self.licenseRecord != nil && self.isPro {
                await validateOnline()
            }
        }
    }

    // MARK: - Product Info

    /// Fetches up-to-date pricing and product info from the licensing proxy.
    public func fetchProductInfo() async {
        let url = proxyBaseURL.appendingPathComponent("api/v1/products")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return
            }

            let products = try JSONDecoder().decode([ProductTierInfo].self, from: data)
            if let current = products.first(where: { $0.id == productId }) {
                await MainActor.run {
                    self.productInfo = current
                }
            }
        } catch {
            // Silently tolerate offline / fetch failures
        }
    }

    // MARK: - In-App Checkout Flow

    /// Initiates an in-app Stripe Checkout session.
    @MainActor
    public func startCheckout() async throws -> (URL, String) {
        isCheckingOut = true
        defer { isCheckingOut = false }

        let endpoint = proxyBaseURL
            .appendingPathComponent("api/v1")
            .appendingPathComponent(productId)
            .appendingPathComponent("checkout/create-session")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let reqPayload = CreateCheckoutRequest(
            machineId: DeviceFingerprint.getHashedFingerprint(),
            machineName: DeviceFingerprint.getMachineName()
        )
        request.httpBody = try JSONEncoder().encode(reqPayload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LicenseError.networkError("Invalid server response")
        }

        if http.statusCode != 200 {
            if let errResp = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw LicenseError.serverError(errResp.error)
            }
            throw LicenseError.serverError("Checkout creation failed (HTTP \(http.statusCode))")
        }

        let checkoutResp = try JSONDecoder().decode(CreateCheckoutResponse.self, from: data)
        guard let checkoutURL = URL(string: checkoutResp.checkoutUrl) else {
            throw LicenseError.serverError("Invalid checkout URL received")
        }

        self.activeCheckoutURL = checkoutURL
        self.activeCheckoutSessionId = checkoutResp.sessionId
        return (checkoutURL, checkoutResp.sessionId)
    }

    /// Polls the checkout session status until completed or still pending.
    @discardableResult
    public func pollCheckoutStatus(sessionId: String) async throws -> LicenseRecord? {
        var components = URLComponents(
            url: proxyBaseURL
                .appendingPathComponent("api/v1")
                .appendingPathComponent(productId)
                .appendingPathComponent("checkout/status"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "session_id", value: sessionId)]

        guard let url = components?.url else {
            throw LicenseError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw LicenseError.networkError("Status check request failed")
        }

        let statusResp = try JSONDecoder().decode(SessionStatusResponse.self, from: data)
        if statusResp.status == "completed", let key = statusResp.licenseKey {
            let record = LicenseRecord(
                licenseKey: key,
                licenseId: statusResp.licenseId,
                machineFingerprint: DeviceFingerprint.getHashedFingerprint(),
                machineName: DeviceFingerprint.getMachineName(),
                activatedAt: Date(),
                productId: productId,
                status: "active"
            )

            LicenseStorage.saveLicense(record)

            await MainActor.run {
                self.isPro = true
                self.licenseRecord = record
                self.activeCheckoutURL = nil
                self.activeCheckoutSessionId = nil
                NotificationCenter.default.post(name: .proLicenseStateChanged, object: nil)
            }
            return record
        }

        return nil
    }

    // MARK: - 7-Day Free Trial

    /// Activates a 7-day free trial on Keygen and locks it to this machine.
    @MainActor
    public func startTrial() async throws {
        isStartingTrial = true
        trialError = nil
        defer { isStartingTrial = false }

        let endpoint = proxyBaseURL
            .appendingPathComponent("api/v1")
            .appendingPathComponent(productId)
            .appendingPathComponent("trial/start")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let reqPayload = StartTrialRequest(
            machineId: DeviceFingerprint.getHashedFingerprint(),
            machineName: DeviceFingerprint.getMachineName()
        )
        request.httpBody = try JSONEncoder().encode(reqPayload)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                let err = "Invalid response from server"
                self.trialError = err
                throw LicenseError.networkError(err)
            }

            if http.statusCode != 200 {
                if let errResp = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                    self.trialError = errResp.error
                    throw LicenseError.serverError(errResp.error)
                }
                let generic = "Trial activation failed (HTTP \(http.statusCode))."
                self.trialError = generic
                throw LicenseError.serverError(generic)
            }

            let trialResp = try JSONDecoder().decode(StartTrialResponse.self, from: data)
            let cleanedKey = trialResp.licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)

            // Verify cryptographic signature locally
            if KeygenCrypto.isCryptographicLicense(cleanedKey) {
                let result = KeygenCrypto.verifySignedKey(cleanedKey)
                guard result.isValid else {
                    let err = result.errorMessage ?? "Invalid cryptographic signature on trial key."
                    self.trialError = err
                    throw LicenseError.invalidKey(err)
                }
            }

            let record = LicenseRecord(
                licenseKey: cleanedKey,
                licenseId: trialResp.licenseId,
                machineFingerprint: DeviceFingerprint.getHashedFingerprint(),
                machineName: DeviceFingerprint.getMachineName(),
                activatedAt: Date(),
                productId: productId,
                status: "trial"
            )

            LicenseStorage.saveLicense(record)
            self.hasUsedTrial = true
            self.isPro = true
            self.licenseRecord = record
            self.trialError = nil
            NotificationCenter.default.post(name: .proLicenseStateChanged, object: nil)
        } catch {
            if let licErr = error as? LicenseError {
                throw licErr
            }
            let netErr = error.localizedDescription
            self.trialError = netErr
            throw LicenseError.networkError(netErr)
        }
    }

    /// Checks if active trial license has expired, updating state if so.
    @MainActor
    public func checkTrialExpiration() {
        guard let record = licenseRecord, record.isTrial else { return }
        if record.isExpired {
            self.isPro = false
            let expiredRecord = LicenseRecord(
                licenseKey: record.licenseKey,
                licenseId: record.licenseId,
                machineFingerprint: record.machineFingerprint,
                machineName: record.machineName,
                activatedAt: record.activatedAt,
                productId: record.productId,
                status: "expired"
            )
            LicenseStorage.saveLicense(expiredRecord)
            self.licenseRecord = expiredRecord
            NotificationCenter.default.post(name: .proLicenseStateChanged, object: nil)
        }
    }

    // MARK: - Manual Key Activation

    /// Activates an existing license key or signed certificate on this machine.
    @MainActor
    public func activateLicenseKey(_ key: String) async throws {
        let cleanedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedKey.isEmpty else {
            throw LicenseError.invalidKey("Please enter a valid license key.")
        }

        isActivating = true
        activationError = nil
        defer { isActivating = false }

        // 1. If key is cryptographically signed with Ed25519, verify signature locally first
        var cryptoResult: KeygenVerificationResult? = nil
        if KeygenCrypto.isCryptographicLicense(cleanedKey) {
            if cleanedKey.hasPrefix("key/") {
                let result = KeygenCrypto.verifySignedKey(cleanedKey)
                guard result.isValid else {
                    let err = result.errorMessage ?? "Invalid cryptographic signature"
                    self.activationError = err
                    throw LicenseError.invalidKey(err)
                }
                cryptoResult = result
            } else if cleanedKey.contains("BEGIN") {
                let result = KeygenCrypto.verifyLicenseFile(cleanedKey)
                guard result.isValid else {
                    let err = result.errorMessage ?? "Invalid license file certificate signature"
                    self.activationError = err
                    throw LicenseError.invalidKey(err)
                }
                cryptoResult = result
            }
        }

        // 2. Attempt online activation with Keygen proxy
        let endpoint = proxyBaseURL
            .appendingPathComponent("api/v1")
            .appendingPathComponent(productId)
            .appendingPathComponent("license/activate")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let reqPayload = ActivateLicenseRequest(
            licenseKey: cleanedKey,
            machineId: DeviceFingerprint.getHashedFingerprint(),
            machineName: DeviceFingerprint.getMachineName()
        )
        request.httpBody = try JSONEncoder().encode(reqPayload)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw LicenseError.networkError("Invalid server response")
            }

            if http.statusCode != 200 {
                if let errResp = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                    self.activationError = errResp.error
                    throw LicenseError.serverError(errResp.error)
                }
                let genericErr = "Activation failed with status code \(http.statusCode)."
                self.activationError = genericErr
                throw LicenseError.serverError(genericErr)
            }

            let actResp = try JSONDecoder().decode(LicenseActionResponse.self, from: data)
            let record = LicenseRecord(
                licenseKey: cleanedKey,
                licenseId: actResp.licenseId ?? cryptoResult?.licenseId,
                machineFingerprint: DeviceFingerprint.getHashedFingerprint(),
                machineName: DeviceFingerprint.getMachineName(),
                activatedAt: Date(),
                productId: productId,
                status: "active"
            )

            LicenseStorage.saveLicense(record)

            self.isPro = true
            self.licenseRecord = record
            self.activationError = nil
            NotificationCenter.default.post(name: .proLicenseStateChanged, object: nil)
        } catch {
            // If offline, but we verified a genuine Ed25519 cryptographic signature, activate locally!
            if cryptoResult?.isValid == true {
                let record = LicenseRecord(
                    licenseKey: cleanedKey,
                    licenseId: cryptoResult?.licenseId,
                    machineFingerprint: DeviceFingerprint.getHashedFingerprint(),
                    machineName: DeviceFingerprint.getMachineName(),
                    activatedAt: Date(),
                    productId: productId,
                    status: "active"
                )

                LicenseStorage.saveLicense(record)

                self.isPro = true
                self.licenseRecord = record
                self.activationError = nil
                NotificationCenter.default.post(name: .proLicenseStateChanged, object: nil)
                return
            }

            if let licErr = error as? LicenseError {
                throw licErr
            }
            throw LicenseError.networkError(error.localizedDescription)
        }
    }

    // MARK: - Deactivation

    /// Deactivates this machine, releasing the seat on Keygen and wiping the local license cache.
    @MainActor
    public func deactivateLicense() async throws {
        guard let current = licenseRecord else { return }

        let endpoint = proxyBaseURL
            .appendingPathComponent("api/v1")
            .appendingPathComponent(productId)
            .appendingPathComponent("license/deactivate")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let reqPayload = DeactivateLicenseRequest(
            licenseKey: current.licenseKey,
            machineId: current.machineFingerprint
        )
        request.httpBody = try JSONEncoder().encode(reqPayload)

        // Best effort remote call — even if offline, we delete locally
        _ = try? await URLSession.shared.data(for: request)

        LicenseStorage.deleteLicense()
        self.isPro = false
        self.licenseRecord = nil
        NotificationCenter.default.post(name: .proLicenseStateChanged, object: nil)
    }

    // MARK: - Online Validation

    /// Validates the current license online with Keygen.
    public func validateOnline() async {
        guard let current = licenseRecord else { return }

        let endpoint = proxyBaseURL
            .appendingPathComponent("api/v1")
            .appendingPathComponent(productId)
            .appendingPathComponent("license/validate")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let reqPayload = ValidateLicenseRequest(
            licenseKey: current.licenseKey,
            machineId: current.machineFingerprint
        )

        guard let body = try? JSONEncoder().encode(reqPayload) else { return }
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }

            if http.statusCode == 200 {
                let valResp = try JSONDecoder().decode(LicenseActionResponse.self, from: data)
                if valResp.valid == false {
                    // License was revoked, expired, suspended, or machine was removed from dashboard
                    if current.isTrial {
                        let expiredRecord = LicenseRecord(
                            licenseKey: current.licenseKey,
                            licenseId: current.licenseId,
                            machineFingerprint: current.machineFingerprint,
                            machineName: current.machineName,
                            activatedAt: current.activatedAt,
                            productId: current.productId,
                            status: "expired"
                        )
                        LicenseStorage.saveLicense(expiredRecord)
                        await MainActor.run {
                            self.isPro = false
                            self.licenseRecord = expiredRecord
                            NotificationCenter.default.post(name: .proLicenseStateChanged, object: nil)
                        }
                    } else {
                        LicenseStorage.deleteLicense()
                        await MainActor.run {
                            self.isPro = false
                            self.licenseRecord = nil
                            NotificationCenter.default.post(name: .proLicenseStateChanged, object: nil)
                        }
                    }
                }
            } else if http.statusCode == 400 || http.statusCode == 404 {
                // If this is a cryptographically signed offline license (.lic certificate or key/...),
                // a 400/404 from the proxy server must NOT delete the offline license.
                let isCrypto = KeygenCrypto.isCryptographicLicense(current.licenseKey)
                if !isCrypto {
                    LicenseStorage.deleteLicense()
                    await MainActor.run {
                        self.isPro = false
                        self.licenseRecord = nil
                        NotificationCenter.default.post(name: .proLicenseStateChanged, object: nil)
                    }
                }
            }
        } catch {
            // Keep offline license intact on network error
        }
    }
}

// MARK: - Error Types

public enum LicenseError: LocalizedError, Sendable {
    case invalidKey(String)
    case networkError(String)
    case serverError(String)
    case invalidURL

    public var errorDescription: String? {
        switch self {
        case .invalidKey(let msg): return msg
        case .networkError(let msg): return "Network error: \(msg)"
        case .serverError(let msg): return msg
        case .invalidURL: return "Invalid service URL"
        }
    }
}
