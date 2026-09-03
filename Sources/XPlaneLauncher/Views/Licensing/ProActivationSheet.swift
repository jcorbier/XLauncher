//
//  ProActivationSheet.swift
//  XPlaneLauncher
//
//  Modal dialog for purchasing XLauncher Pro with a dedicated license file activation view.
//

import SwiftUI
import UniformTypeIdentifiers

public enum ProSheetView: String, Identifiable, Hashable, Sendable {
    case purchase
    case activateLicense

    public var id: String { rawValue }
}

struct ProActivationSheet: View {
    @Environment(LicenseManager.self) private var licenseManager
    @Environment(\.dismiss) private var dismiss

    var initialView: ProSheetView = .purchase

    @State private var currentView: ProSheetView = .purchase
    @State private var licenseKeyInput: String = ""
    @State private var isActivating: Bool = false
    @State private var isStartingCheckout: Bool = false
    @State private var errorMessage: String? = nil
    @State private var activeCheckoutData: (url: URL, sessionId: String)? = nil
    @State private var showSuccessBanner: Bool = false
    @State private var isDropTargeted: Bool = false
    @State private var showManualTextInput: Bool = false
    @State private var selectedFileName: String? = nil

    init(initialView: ProSheetView = .purchase) {
        self.initialView = initialView
        self._currentView = State(initialValue: initialView)
    }

    var priceText: String {
        licenseManager.productInfo?.formattedPrice ?? "€5.00"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar
                .padding()
                .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ScrollView {
                switch currentView {
                case .purchase:
                    purchaseView
                        .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)))
                case .activateLicense:
                    activateLicenseView
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
                }
            }
        }
        .frame(width: 520, height: 650)
        .sheet(item: Binding(
            get: { activeCheckoutData.map { CheckoutSessionItem(url: $0.url, sessionId: $0.sessionId) } },
            set: { _ in
                activeCheckoutData = nil
                if licenseManager.isPro {
                    dismiss()
                }
            }
        )) { item in
            StripeCheckoutSheet(
                checkoutURL: item.url,
                sessionId: item.sessionId,
                licenseManager: licenseManager,
                onFinished: {
                    activeCheckoutData = nil
                    dismiss()
                }
            )
        }
        .onChange(of: licenseManager.isPro) { _, isPro in
            if isPro && activeCheckoutData == nil {
                dismiss()
            }
        }
        .onAppear {
            currentView = initialView
        }
        .onChange(of: initialView) { _, newView in
            currentView = newView
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            if currentView == .activateLicense {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        errorMessage = nil
                        currentView = .purchase
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    ProBadgeView(size: 13)
                    Text("XLauncher Pro")
                        .font(.headline)
                }
            }

            Spacer()

            if currentView == .activateLicense {
                Text("Activate License")
                    .font(.headline)
                Spacer()
            }

            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
    }

    // MARK: - Purchase View (Main View)

    private var purchaseView: some View {
        VStack(spacing: 24) {
            // Hero Section
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.2), Color.yellow.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 72, height: 72)
                    Image(systemName: "crown.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.orange, .yellow],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                VStack(spacing: 4) {
                    Text("Upgrade to XLauncher Pro")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Supercharge your flight simulation experience with next-generation scenery streaming and advanced tools.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.top, 8)

            // Feature Highlights
            VStack(alignment: .leading, spacing: 14) {
                FeatureRow(
                    icon: "map.fill",
                    color: .blue,
                    title: "Streaming Orthophoto Engine",
                    description: "Stream high-resolution satellite imagery on demand without multi-terabyte downloads."
                )

                FeatureRow(
                    icon: "laptopcomputer.and.ipad",
                    color: .purple,
                    title: "3 Machine Activations",
                    description: "Use your single lifetime license on up to 3 of your Macs simultaneously."
                )

                FeatureRow(
                    icon: "waveform.path.ecg",
                    color: .green,
                    title: "Enhanced Diagnostics & Profiling",
                    description: "Pinpoint scenery load bottlenecks, crash traces, and SASL/Lua errors."
                )

                FeatureRow(
                    icon: "sparkles",
                    color: .orange,
                    title: "Priority Updates & Early Features",
                    description: "Direct support and immediate access to new platform enhancements."
                )
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.8)
            )

            // Error Message
            if let error = errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding(10)
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Purchase Button
            VStack(spacing: 12) {
                Button(action: {
                    startInAppPurchase()
                }) {
                    HStack {
                        if isStartingCheckout {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "creditcard.fill")
                        }
                        Text("Purchase License (\(priceText) Lifetime)")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isStartingCheckout || isActivating || licenseManager.isPro)

                Text("One-time lifetime payment • Instant activation • Secured by Stripe")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .padding(.top, 4)

            // Link at the very bottom to switch to activation view
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    errorMessage = nil
                    currentView = .activateLicense
                }
            }) {
                HStack(spacing: 4) {
                    Text("Already have a license?")
                        .foregroundStyle(.secondary)
                    Text("Activate with a license file...")
                        .fontWeight(.medium)
                        .foregroundStyle(Color.accentColor)
                }
                .font(.callout)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
        }
        .padding(20)
    }

    // MARK: - Activate License View (Dedicated File View)

    private var activateLicenseView: some View {
        VStack(spacing: 24) {
            // Header Description
            VStack(spacing: 8) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.accentColor)

                Text("Activate XLauncher Pro")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("If you purchased a license from the store or have a license key file, select or drop it below.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .padding(.top, 8)

            // Success Message
            if showSuccessBanner {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("XLauncher Pro successfully activated on this Mac!")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.green)
                    Spacer()
                }
                .padding(10)
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Error Message
            if let error = errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding(10)
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Primary File Drop & Open Card
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isDropTargeted ? Color.accentColor : Color(NSColor.separatorColor),
                        style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: isDropTargeted ? [6] : [])
                    )
                    .background(isDropTargeted ? Color.accentColor.opacity(0.06) : Color(NSColor.controlBackgroundColor))

                VStack(spacing: 12) {
                    Image(systemName: isActivating ? "arrow.triangle.2.circlepath" : "doc.text.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(isDropTargeted ? Color.accentColor : .secondary)

                    VStack(spacing: 3) {
                        Text("Select License Key File")
                            .font(.headline)
                        Text("Supports .lic, .key, or text license files")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let fileName = selectedFileName {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(fileName)
                                .fontWeight(.medium)
                        }
                        .font(.caption)
                    }

                    Button(action: {
                        openLicenseFile()
                    }) {
                        if isActivating {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Activating...")
                            }
                        } else {
                            Label("Open License File...", systemImage: "folder")
                                .fontWeight(.medium)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(isActivating || licenseManager.isPro)
                    .padding(.top, 4)
                }
                .padding(24)
            }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDroppedFile(providers: providers)
            }

            // Collapsible Manual Key Entry (Alternative)
            DisclosureGroup("Or enter license key as text", isExpanded: $showManualTextInput) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("Paste key or certificate string here", text: $licenseKeyInput)
                            .fontDesign(.monospaced)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isActivating || licenseManager.isPro)

                        Button("Paste") {
                            if let pasted = NSPasteboard.general.string(forType: .string) {
                                licenseKeyInput = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                        .controlSize(.regular)
                        .disabled(isActivating || licenseManager.isPro)

                        Button(action: {
                            activateWithKey(licenseKeyInput)
                        }) {
                            if isActivating {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Activate")
                                    .fontWeight(.semibold)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .disabled(licenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isActivating || licenseManager.isPro)
                    }
                }
                .padding(.top, 6)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.8)
            )
        }
        .padding(20)
    }

    // MARK: - Actions & File Handlers

    private func openLicenseFile() {
        let panel = NSOpenPanel()
        panel.title = "Select License Key File"
        panel.prompt = "Activate License"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            .plainText,
            .item,
            UTType(filenameExtension: "lic") ?? .item,
            UTType(filenameExtension: "key") ?? .item,
            UTType(filenameExtension: "license") ?? .item
        ]

        if panel.runModal() == .OK, let url = panel.url {
            activateFromFile(url: url)
        }
    }

    private func handleDroppedFile(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier("public.file-url") }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            var fileURL: URL?
            if let data = item as? Data {
                fileURL = URL(dataRepresentation: data, relativeTo: nil)
            } else if let url = item as? URL {
                fileURL = url
            }

            guard let url = fileURL else { return }
            Task { @MainActor in
                activateFromFile(url: url)
            }
        }
        return true
    }

    private func activateFromFile(url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                errorMessage = "The selected file is empty."
                return
            }
            selectedFileName = url.lastPathComponent
            licenseKeyInput = trimmed
            activateWithKey(trimmed)
        } catch {
            errorMessage = "Could not read license file: \(error.localizedDescription)"
        }
    }

    private func activateWithKey(_ key: String) {
        errorMessage = nil
        isActivating = true

        Task {
            do {
                try await licenseManager.activateLicenseKey(key)
                await MainActor.run {
                    self.isActivating = false
                    self.showSuccessBanner = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    self.isActivating = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func startInAppPurchase() {
        errorMessage = nil
        isStartingCheckout = true

        Task {
            do {
                let (url, sessionId) = try await licenseManager.startCheckout()
                await MainActor.run {
                    self.isStartingCheckout = false
                    self.activeCheckoutData = (url: url, sessionId: sessionId)
                }
            } catch {
                await MainActor.run {
                    self.isStartingCheckout = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Helper Views

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct CheckoutSessionItem: Identifiable {
    let id = UUID()
    let url: URL
    let sessionId: String
}
