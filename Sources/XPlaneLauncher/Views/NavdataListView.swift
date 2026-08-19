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

import SwiftUI

struct NavdataListView: View {
    @Environment(NavdataManager.self) var navdataManager
    @Environment(NavigraphAuthManager.self) var authManager

    @State private var searchText: String = ""
    @State private var showLoginSheet: Bool = false
    @State private var showBackupsSheet: Bool = false
    @State private var showAddMappingSheet: Bool = false
    @State private var showDebugConsole: Bool = false

    var filteredAddons: [DetectedNavdataItem] {
        if searchText.isEmpty {
            return navdataManager.addons
        }
        let query = searchText.lowercased()
        return navdataManager.addons.filter {
            $0.definition.name.lowercased().contains(query) ||
            $0.definition.formatKey.lowercased().contains(query) ||
            $0.definition.relativeTargetPath.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                Label("Navigation Data", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.title3)
                    .fontWeight(.bold)

                if !navdataManager.addons.isEmpty {
                    let updatesCount = navdataManager.addons.filter { $0.isUpdateAvailable }.count
                    Text("\(navdataManager.addons.count) Addons • \(updatesCount) Updates Available")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer()

                // Search Field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search navdata addons...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(width: 180)

                Button(action: {
                    showAddMappingSheet = true
                }) {
                    Label("Add Mapping", systemImage: "plus")
                }

                Button(action: {
                    showBackupsSheet = true
                }) {
                    Label("Backups (\(navdataManager.backups.count))", systemImage: "clock.arrow.circlepath")
                }

                Button(action: {
                    Task {
                        await navdataManager.checkOnlinePackages()
                    }
                }) {
                    Label("Check Cycles", systemImage: "arrow.clockwise")
                }
                .disabled(navdataManager.isFetchingPackages || navdataManager.isUpdatingAny)

                Button(action: {
                    Task {
                        await navdataManager.updateAllAddons()
                    }
                }) {
                    Label("Update All", systemImage: "square.and.arrow.down")
                }
                .disabled(!navdataManager.hasUpdatesAvailable || navdataManager.isUpdatingAny)

                Button(action: {
                    showDebugConsole.toggle()
                }) {
                    Label("Console", systemImage: showDebugConsole ? "terminal.fill" : "terminal")
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Navigraph Account Status Banner
            NavigraphAccountBanner(
                authManager: authManager,
                navdataManager: navdataManager,
                showLoginSheet: $showLoginSheet
            )

            Divider()

            // Main Addon List
            if navdataManager.addons.isEmpty {
                ContentUnavailableView {
                    Label("No Navdata Addons Found", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                } description: {
                    Text("Select a valid X-Plane 12 folder in Settings or click 'Add Mapping' to add a custom navdata location.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredAddons) { item in
                        NavdataAddonRow(item: item)
                            .contextMenu {
                                if item.definition.id != "17271467-ff15-4302-82a6-946b0ffe2aec" {
                                    Button(role: .destructive) {
                                        navdataManager.deleteCustomMapping(id: item.definition.id)
                                    } label: {
                                        Label("Remove Mapping", systemImage: "trash")
                                    }
                                }
                                Button {
                                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: item.targetURL.path)
                                } label: {
                                    Label("Show in Finder", systemImage: "folder")
                                }
                            }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }

            // Bottom Debug Console
            if showDebugConsole {
                Divider()
                ConsoleView(title: "Navdata Log", logger: navdataManager.logger, initialCategory: .navdata)
                    .frame(height: 180)
            }
        }
        .sheet(isPresented: $showLoginSheet) {
            NavigraphLoginSheet()
                .environment(authManager)
                .environment(navdataManager)
        }
        .sheet(isPresented: $showBackupsSheet) {
            NavdataBackupsSheet()
                .environment(navdataManager)
        }
        .sheet(isPresented: $showAddMappingSheet) {
            AddCustomMappingSheet()
                .environment(navdataManager)
        }
    }
}

// MARK: - Account Banner

private struct NavigraphAccountBanner: View {
    let authManager: NavigraphAuthManager
    let navdataManager: NavdataManager
    @Binding var showLoginSheet: Bool

    var body: some View {
        HStack(spacing: 16) {
            switch authManager.authState {
            case .authenticated(let user):
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Connected to Navigraph")
                            .font(.headline)
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(user.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        if let region = user.preferredRegion {
                            Text("[\(region)]")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let cycleInfo = navdataManager.currentCycleInfo {
                        Text("Active AIRAC: Cycle \(cycleInfo.cycle) (\(cycleInfo.cycleInternalId))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button("Sign Out") {
                    authManager.signOut()
                    navdataManager.scanAndRefresh()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

            case .authenticating:
                ProgressView()
                    .controlSize(.small)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Signing in to Navigraph...")
                        .font(.headline)
                    Text("Authenticating with One-Time Password.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

            case .unauthenticated, .error:
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Navigraph Account Not Connected")
                        .font(.headline)
                    Text("Sign in with your Navigraph One-Time Password (OTP) to download and update AIRAC cycles directly.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: {
                    showLoginSheet = true
                }) {
                    Label("Sign In with Navigraph", systemImage: "key.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
    }
}

// MARK: - Navigraph Login Sheet

private struct NavigraphLoginSheet: View {
    @Environment(NavigraphAuthManager.self) var authManager
    @Environment(NavdataManager.self) var navdataManager
    @Environment(\.dismiss) var dismiss

    @State private var email: String = ""
    @State private var otp: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String? = nil

    private let otpURL = URL(string: "https://navigraph.com/account/otp")!

    var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !otp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Header Icon & Title
                VStack(spacing: 8) {
                    Image(systemName: "key.horizontal.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.accentColor)

                    Text("Sign In with Navigraph")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Authenticate using a One-Time Password (OTP) from your Navigraph account.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }
                .padding(.top, 10)

                // Step-by-Step Instructions
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        Text("1")
                            .font(.caption)
                            .fontWeight(.bold)
                            .frame(width: 22, height: 22)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Generate a One-Time Password")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Visit the Navigraph account portal in your browser while signed in.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button(action: {
                                NSWorkspace.shared.open(otpURL)
                            }) {
                                Label("Open navigraph.com/account/otp", systemImage: "arrow.up.right.square")
                            }
                            .buttonStyle(.link)
                            .controlSize(.small)
                            .padding(.top, 2)
                        }
                    }

                    Divider()

                    HStack(alignment: .top, spacing: 12) {
                        Text("2")
                            .font(.caption)
                            .fontWeight(.bold)
                            .frame(width: 22, height: 22)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Enter Credentials")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Email Address / Username:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("e.g. user@example.com", text: $email)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("One-Time Password (OTP):")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("e.g. ABCDEF", text: $otp)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                if let errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                Spacer()

                // Actions
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button(action: {
                        performLogin()
                    }) {
                        if isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                                .frame(minWidth: 80)
                        } else {
                            Text("Sign In")
                                .frame(minWidth: 80)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isFormValid || isSubmitting)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 480, height: 500)
            .onAppear {
                self.email = authManager.savedEmail
            }
        }
    }

    private func performLogin() {
        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                try await authManager.authenticate(email: email, otp: otp)
                await navdataManager.checkOnlinePackages()
                isSubmitting = false
                dismiss()
            } catch {
                isSubmitting = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Addon Row

private struct NavdataAddonRow: View {
    let item: DetectedNavdataItem
    @Environment(NavdataManager.self) var navdataManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                // Icon
                Image(systemName: item.definition.isCustom ? "cube.transparent" : "airplane.circle")
                    .font(.title2)
                    .foregroundStyle(item.isUpdateAvailable ? Color.orange : (item.isInstalled ? Color.green : Color.secondary))
                    .frame(width: 32)

                // Addon Info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(item.definition.name)
                            .font(.body)
                            .fontWeight(.semibold)

                        if item.definition.isCustom {
                            Text("Custom")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.purple.opacity(0.15))
                                .foregroundStyle(.purple)
                                .clipShape(Capsule())
                        }
                    }

                    HStack(spacing: 6) {
                        Text("Target: \(item.definition.relativeTargetPath)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let airac = item.currentAirac {
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text(airac)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                // Cycles
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Installed:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.currentCycle.map { "Cycle \($0)" } ?? "None")
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.medium)
                            .foregroundStyle(item.currentCycle != nil ? .primary : .secondary)
                    }

                    if let latest = item.latestCycle {
                        HStack(spacing: 6) {
                            Text("Latest:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Cycle \(latest)")
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundStyle(item.isUpdateAvailable ? .orange : .green)
                        }
                    }
                }
                .frame(width: 140, alignment: .trailing)

                // Action Button
                if item.isUpdating {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 80)
                } else if item.isUpdateAvailable {
                    Button(action: {
                        Task {
                            await navdataManager.updateAddon(item)
                        }
                    }) {
                        Text(item.isInstalled ? "Update" : "Install")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .frame(width: 80)
                } else if item.isInstalled {
                    Button(action: {
                        Task {
                            await navdataManager.updateAddon(item)
                        }
                    }) {
                        Text("Reinstall")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(width: 80)
                } else {
                    Text("Unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 80)
                }
            }

            // Progress Bar & Status
            if item.isUpdating {
                VStack(alignment: .leading, spacing: 2) {
                    ProgressView(value: item.progress)
                        .progressViewStyle(.linear)
                    Text(item.statusMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 44)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Backups Sheet

private struct NavdataBackupsSheet: View {
    @Environment(NavdataManager.self) var navdataManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if navdataManager.backups.isEmpty {
                    ContentUnavailableView {
                        Label("No Backups Found", systemImage: "clock.arrow.circlepath")
                    } description: {
                        Text("When you update navdata packages, a backup of the previous cycle will be saved here automatically.")
                    }
                } else {
                    List {
                        ForEach(navdataManager.backups) { backup in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(backup.verification.provider_name)
                                        .font(.headline)

                                    HStack(spacing: 8) {
                                        if let cycle = backup.verification.cycle {
                                            Text("Cycle: \(cycle)")
                                                .font(.caption)
                                                .fontWeight(.medium)
                                        }
                                        Text("•")
                                            .foregroundStyle(.secondary)
                                        Text("\(backup.verification.file_count) files")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("•")
                                            .foregroundStyle(.secondary)
                                        Text(backup.formattedDate)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Button("Restore") {
                                    do {
                                        try navdataManager.restoreBackup(backup)
                                    } catch {
                                        ConsoleLogger.shared.log("Failed to restore backup: \(error.localizedDescription)", category: .navdata, level: .error)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)

                                Button(role: .destructive) {
                                    navdataManager.deleteBackup(backup)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Navdata Backups & Rollback")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .frame(minWidth: 500, minHeight: 350)
        }
    }
}

// MARK: - Add Custom Mapping Sheet

private struct AddCustomMappingSheet: View {
    @Environment(NavdataManager.self) var navdataManager
    @Environment(\.dismiss) var dismiss

    @State private var selectedAddonGuid: String = ""
    @State private var customName: String = ""
    @State private var customFormatKey: String = ""
    @State private var targetPath: String = ""

    private var selectedAddon: FMSAddonDefinition? {
        navdataManager.supportedXP12Addons.first { $0.guid == selectedAddonGuid }
    }

    private var isCustomMode: Bool {
        selectedAddonGuid == "custom"
    }

    private var isValid: Bool {
        let path = targetPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return false }
        if isCustomMode {
            let name = customName.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = customFormatKey.trimmingCharacters(in: .whitespacesAndNewlines)
            return !name.isEmpty && !key.isEmpty
        }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Addon Selection") {
                    Picker("Add-on", selection: $selectedAddonGuid) {
                        ForEach(navdataManager.supportedXP12Addons, id: \.guid) { addon in
                            Text(addon.name).tag(addon.guid)
                        }
                        Divider()
                        Text("Custom Mapping").tag("custom")
                    }
                    .onChange(of: selectedAddonGuid) { _, newGuid in
                        updatePathForSelection(guid: newGuid)
                    }
                }

                if isCustomMode {
                    Section("Custom Addon Details") {
                        TextField("Addon Display Name (e.g. Toliss A321 Custom)", text: $customName)
                        TextField("Navigraph Format Key (e.g. x-plane12, gns430, ufmc)", text: $customFormatKey)
                    }
                }

                Section("Target Location") {
                    HStack {
                        TextField("Path to Add-on", text: $targetPath)
                        Button("Browse...") {
                            selectFolder()
                        }
                    }
                    Text(isCustomMode
                        ? "Relative path in X-Plane (or absolute path) where navigation data will be installed."
                        : "Computed path for this add-on in X-Plane. You can customize or browse if your aircraft is in a different folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Navdata Mapping")
            .onAppear {
                if selectedAddonGuid.isEmpty {
                    if let first = navdataManager.supportedXP12Addons.first {
                        selectedAddonGuid = first.guid
                        updatePathForSelection(guid: first.guid)
                    } else {
                        selectedAddonGuid = "custom"
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if isCustomMode {
                            navdataManager.addMapping(
                                addon: nil,
                                name: customName.trimmingCharacters(in: .whitespacesAndNewlines),
                                formatKey: customFormatKey.trimmingCharacters(in: .whitespacesAndNewlines),
                                relativeTargetPath: targetPath.trimmingCharacters(in: .whitespacesAndNewlines)
                            )
                        } else if let addon = selectedAddon {
                            navdataManager.addMapping(
                                addon: addon,
                                name: "",
                                formatKey: "",
                                relativeTargetPath: targetPath.trimmingCharacters(in: .whitespacesAndNewlines)
                            )
                        }
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .frame(minWidth: 480, minHeight: 300)
        }
    }

    private func updatePathForSelection(guid: String) {
        if guid == "custom" {
            if targetPath.isEmpty {
                targetPath = "Custom Data"
            }
        } else if let addon = navdataManager.supportedXP12Addons.first(where: { $0.guid == guid }) {
            targetPath = navdataManager.computeSuggestedPath(for: addon)
        }
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if let xp = navdataManager.xPlaneURL {
            panel.directoryURL = xp
        }
        if panel.runModal() == .OK, let selectedURL = panel.url {
            if let xp = navdataManager.xPlaneURL, selectedURL.path.hasPrefix(xp.path) {
                var rel = selectedURL.path.replacingOccurrences(of: xp.path, with: "")
                while rel.hasPrefix("/") { rel.removeFirst() }
                targetPath = rel
            } else {
                targetPath = selectedURL.path
            }
        }
    }
}
