//
//  StripeCheckoutSheet.swift
//  XPlaneLauncher
//
//  Native sheet embedding WKWebView for frictionless in-app Stripe Checkout,
//  real-time payment status polling, and automatic Pro unlocking.
//

import SwiftUI
import WebKit
import UniformTypeIdentifiers

struct StripeCheckoutSheet: View {
    @Environment(\.dismiss) private var dismiss
    let checkoutURL: URL
    let sessionId: String
    let licenseManager: LicenseManager
    var onFinished: (() -> Void)? = nil

    @State private var isLoadingWebPage: Bool = true
    @State private var isPaymentCompleted: Bool = false
    @State private var isFinalizingActivation: Bool = false
    @State private var copiedKey: Bool = false
    @State private var pollingTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: isPaymentCompleted ? "checkmark.seal.fill" : "creditcard.fill")
                        .foregroundStyle(isPaymentCompleted ? .green : .blue)
                    Text(isPaymentCompleted ? "Purchase Complete" : "XLauncher Pro Checkout")
                        .font(.headline)
                }

                Spacer()

                Button(isPaymentCompleted ? "Done" : "Cancel") {
                    pollingTask?.cancel()
                    if isPaymentCompleted {
                        if let onFinished {
                            onFinished()
                        } else {
                            dismiss()
                        }
                    } else {
                        dismiss()
                    }
                }
                .keyboardShortcut(isPaymentCompleted ? .defaultAction : .cancelAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if isPaymentCompleted {
                // Celebration & Success View
                celebrationView
            } else {
                // Checkout Web View with Live Activation Overlays
                ZStack {
                    StripeWebViewRepresentable(
                        url: checkoutURL,
                        isLoading: $isLoadingWebPage,
                        onSuccessRedirect: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isFinalizingActivation = true
                            }
                            Task {
                                await checkStatusImmediate()
                            }
                        },
                        onCancelRedirect: {
                            pollingTask?.cancel()
                            dismiss()
                        }
                    )

                    // Initial Page Loading Spinner
                    if isLoadingWebPage {
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.regular)
                            Text("Loading secure checkout...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(NSColor.windowBackgroundColor).opacity(0.85))
                    }

                    // Post-Payment Finalization Overlay
                    if isFinalizingActivation {
                        ZStack {
                            Color.black.opacity(0.35)
                                .ignoresSafeArea()

                            VStack(spacing: 16) {
                                ProgressView()
                                    .controlSize(.large)

                                VStack(spacing: 6) {
                                    Text("Activating XLauncher Pro...")
                                        .font(.headline)

                                    Text("Payment verified! Node-locking license to this Mac...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .padding(24)
                            .frame(width: 300)
                            .background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 6)
                        }
                        .transition(.opacity)
                    }
                }
            }
        }
        .frame(width: 580, height: 680)
        .onAppear {
            startPolling()
        }
        .onDisappear {
            pollingTask?.cancel()
        }
    }

    // MARK: - Celebration View

    private var celebrationView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 90, height: 90)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(.green)
            }

            VStack(spacing: 8) {
                Text("Welcome to XLauncher Pro!")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Your license has been activated and node-locked to this Mac.\nAll Pro features are now unlocked.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let license = licenseManager.licenseRecord {
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("License Key:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(license.maskedKey)
                                .font(.caption)
                                .fontDesign(.monospaced)
                                .fontWeight(.semibold)
                        }
                        HStack {
                            Text("Activated On:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(license.machineName)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                    .frame(width: 320)
                    .padding(4)
                }

                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Button {
                            exportLicenseFile(licenseKey: license.licenseKey)
                        } label: {
                            Label("Save License File...", systemImage: "square.and.arrow.down")
                        }
                        .controlSize(.regular)

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(license.licenseKey, forType: .string)
                            copiedKey = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copiedKey = false
                            }
                        } label: {
                            Label(copiedKey ? "Copied!" : "Copy Key", systemImage: copiedKey ? "checkmark" : "doc.on.doc")
                        }
                        .controlSize(.regular)
                    }

                    Text("Save your license file to activate on up to 2 other Macs.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Button("Start Using XLauncher Pro") {
                if let onFinished {
                    onFinished()
                } else {
                    dismiss()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func exportLicenseFile(licenseKey: String) {
        let savePanel = NSSavePanel()
        savePanel.title = "Save XLauncher Pro License File"
        savePanel.nameFieldStringValue = "xlauncher.lic"
        savePanel.prompt = "Save License"
        savePanel.allowedContentTypes = [
            .plainText,
            .item,
            UTType(filenameExtension: "lic") ?? .item
        ]

        if savePanel.runModal() == .OK, let url = savePanel.url {
            try? licenseKey.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Status Polling

    private func startPolling() {
        pollingTask = Task {
            // Initial delay while checkout webpage loads
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            while !Task.isCancelled && !isPaymentCompleted {
                await checkStatusOnce()
                if isPaymentCompleted || Task.isCancelled { break }

                let interval: UInt64 = isFinalizingActivation ? 1_500_000_000 : 2_500_000_000
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    private func checkStatusImmediate() async {
        await checkStatusOnce()
    }

    private func checkStatusOnce() async {
        do {
            if let _ = try await licenseManager.pollCheckoutStatus(sessionId: sessionId) {
                await MainActor.run {
                    withAnimation {
                        self.isFinalizingActivation = false
                        self.isPaymentCompleted = true
                    }
                }
            }
        } catch {
            // Silently continue polling on transient network hiccup
        }
    }
}

// MARK: - WKWebView Representable

struct StripeWebViewRepresentable: NSViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    let onSuccessRedirect: () -> Void
    let onCancelRedirect: () -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: StripeWebViewRepresentable

        init(_ parent: StripeWebViewRepresentable) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            self.parent.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            self.parent.isLoading = false
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            if let destURL = navigationAction.request.url {
                if destURL.absoluteString.contains("/checkout/success") {
                    parent.onSuccessRedirect()
                    decisionHandler(.cancel)
                    return
                }
                if destURL.absoluteString.contains("/checkout/cancel") {
                    parent.onCancelRedirect()
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }
    }
}
