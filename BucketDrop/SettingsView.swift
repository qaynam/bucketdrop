//
//  SettingsView.swift
//  BucketDrop
//
//  Created by Fayaz Ahmed Aralikatti on 12/01/26.
//

import SwiftUI
import AppKit

struct SettingsView: View {
    var settings = SettingsManager.shared

    @State private var accessKeyId: String = ""
    @State private var secretAccessKey: String = ""
    @State private var bucket: String = ""
    @State private var region: String = ""
    @State private var endpoint: String = ""
    @State private var publicUrlBase: String = ""
    @State private var folderPrefix: String = ""

    @State private var isTesting = false
    @State private var testResult: TestResult?
    @State private var selection: SettingsSection? = .credentials
    @State private var didSave = false

    enum TestResult {
        case success
        case failure(String)
    }

    enum SettingsSection: String, CaseIterable, Identifiable {
        case credentials
        case storage
        case about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .credentials: return "Credentials"
            case .storage: return "Storage"
            case .about: return "About"
            }
        }

        var icon: String {
            switch self {
            case .credentials: return "key.fill"
            case .storage: return "externaldrive.connected.to.line.below"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(180)
        } detail: {
            VStack(spacing: 0) {
                Group {
                    switch selection ?? .credentials {
                    case .credentials: credentialsPane
                    case .storage: storagePane
                    case .about: aboutPane
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if (selection ?? .credentials) != .about {
                    Divider()
                    bottomBar
                }
            }
        }
        .navigationTitle("BucketDrop Settings")
        .frame(width: 640, height: 470)
        .onAppear { loadSettings() }
    }

    // MARK: - Panes

    private var credentialsPane: some View {
        Form {
            Section {
                labeledField("Access Key ID", text: $accessKeyId, secure: true)
                labeledField("Secret Access Key", text: $secretAccessKey, secure: true)
                labeledField("Bucket Name", text: $bucket)
                labeledField("Region", text: $region, prompt: "us-east-1")
            } header: {
                Text("S3 Credentials")
            } footer: {
                Text("Your keys are stored securely in the macOS Keychain.")
            }
        }
        .formStyle(.grouped)
    }

    private var storagePane: some View {
        Form {
            Section {
                labeledField("S3 Endpoint", text: $endpoint, prompt: "https://xxx.r2.cloudflarestorage.com")
                labeledField("Public URL Base", text: $publicUrlBase, prompt: "https://static.example.com")
                labeledField("Folder / Prefix (optional)", text: $folderPrefix, prompt: "mac")
            } header: {
                Text("S3-Compatible (R2, MinIO, etc.)")
            } footer: {
                Text("For Cloudflare R2: paste the S3 API endpoint URL and set region to 'auto'. Public URL Base is your custom domain for accessing files. Folder/Prefix stores files under that path (e.g. 'mac').")
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Download Folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(settings.downloadDirectoryDisplayName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        if settings.hasCustomDownloadDirectory {
                            Button("Use Downloads") {
                                settings.resetDownloadDirectory()
                            }
                        }
                        Button("Choose…") {
                            chooseDownloadFolder()
                        }
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Text("Downloads")
            } footer: {
                Text("Downloaded files are saved here automatically. Defaults to your Downloads folder.")
            }
        }
        .formStyle(.grouped)
    }

    private func chooseDownloadFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose a folder for downloaded files"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            settings.setDownloadDirectory(url)
        }
    }

    // Label-above-input field, like a standard web form
    @ViewBuilder
    private func labeledField(_ label: String, text: Binding<String>, prompt: String? = nil, secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Group {
                if secure {
                    SecureField("", text: text, prompt: prompt.map { Text($0) })
                } else {
                    TextField("", text: text, prompt: prompt.map { Text($0) })
                }
            }
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
        }
        .padding(.vertical, 2)
    }

    private var aboutPane: some View {
        Form {
            Section {
                HStack {
                    AsyncImage(url: URL(string: "https://github.com/fayazara.png")) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Circle()
                            .fill(Color(nsColor: .quaternaryLabelColor))
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fayaz Ahmed")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Link("@fayazara", destination: URL(string: "https://x.com/fayazara")!)
                            .font(.caption)
                    }

                    Spacer()

                    Text("Made in India")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("About")
            }

            Section {
                Button(role: .destructive) {
                    NSApplication.shared.terminate(nil)
                } label: {
                    HStack {
                        Spacer()
                        Label("Quit BucketDrop", systemImage: "power")
                        Spacer()
                    }
                }
            } footer: {
                Text("Quit the app completely. You can reopen it from Applications or Spotlight.")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if isTesting {
                ProgressView()
                    .controlSize(.small)
            }

            if let result = testResult {
                switch result {
                case .success:
                    Label("Connected!", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                case .failure(let error):
                    Label(error, systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }

            Spacer()

            Button("Test Connection") {
                testConnection()
            }
            .disabled(isTesting || accessKeyId.isEmpty || secretAccessKey.isEmpty || bucket.isEmpty)

            Button(didSave ? "Saved!" : "Save") {
                saveSettings()
            }
            .buttonStyle(.borderedProminent)
            .disabled(accessKeyId.isEmpty || secretAccessKey.isEmpty || bucket.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Actions

    private func loadSettings() {
        accessKeyId = settings.accessKeyId
        secretAccessKey = settings.secretAccessKey
        bucket = settings.bucket
        region = settings.region
        endpoint = settings.endpoint
        publicUrlBase = settings.publicUrlBase
        folderPrefix = settings.folderPrefix
    }

    private func saveSettings() {
        settings.accessKeyId = accessKeyId
        settings.secretAccessKey = secretAccessKey
        settings.bucket = bucket
        settings.region = region.isEmpty ? "us-east-1" : region
        settings.endpoint = endpoint
        settings.publicUrlBase = publicUrlBase
        settings.folderPrefix = folderPrefix

        testResult = .success
        withAnimation { didSave = true }

        // Close settings window after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.keyWindow?.close()
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil

        // Temporarily save settings for testing
        let oldAccessKey = settings.accessKeyId
        let oldSecretKey = settings.secretAccessKey
        let oldBucket = settings.bucket
        let oldRegion = settings.region
        let oldEndpoint = settings.endpoint
        let oldPublicUrlBase = settings.publicUrlBase
        let oldFolderPrefix = settings.folderPrefix

        settings.accessKeyId = accessKeyId
        settings.secretAccessKey = secretAccessKey
        settings.bucket = bucket
        settings.region = region.isEmpty ? "us-east-1" : region
        settings.endpoint = endpoint
        settings.publicUrlBase = publicUrlBase
        settings.folderPrefix = folderPrefix

        Task {
            do {
                _ = try await S3Service.shared.listObjects()
                await MainActor.run {
                    testResult = .success
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    // Restore old settings on failure
                    settings.accessKeyId = oldAccessKey
                    settings.secretAccessKey = oldSecretKey
                    settings.bucket = oldBucket
                    settings.region = oldRegion
                    settings.endpoint = oldEndpoint
                    settings.publicUrlBase = oldPublicUrlBase
                    settings.folderPrefix = oldFolderPrefix

                    testResult = .failure(error.localizedDescription)
                    isTesting = false
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
