//
//  ContentView.swift
//  BucketDrop
//
//  Created by Fayaz Ahmed Aralikatti on 12/01/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Combine
import AppKit
import Quartz

// Model to track individual file upload state
struct UploadTask: Identifiable {
    let id = UUID()
    let filename: String
    let url: URL
    var progress: Double = 0
    var status: UploadStatus = .pending
    var resultURL: String?
    
    enum UploadStatus {
        case pending
        case uploading
        case completed
        case failed(String)
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openSettingsAction) private var openSettings
    @Environment(\.openErrorDetailAction) private var openErrorDetail
    @Environment(\.showToastAction) private var showToast
    @Query(sort: \UploadedFile.uploadedAt, order: .reverse) private var uploadedFiles: [UploadedFile]

    var settings = SettingsManager.shared

    @State private var isTargeted = false
    @State private var isUploading = false
    @State private var uploadTasks: [UploadTask] = []
    @State private var errorMessage: String?
    @State private var errorDetail: String?
    @State private var showSettings = false
    @State private var s3Objects: [S3Object] = []
    @State private var isLoadingList = false

    // Pagination / infinite scroll
    @State private var nextToken: String?
    @State private var isLoadingMore = false
    @State private var isLoadingAll = false

    // Search
    @State private var showSearch = false
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @FocusState private var isSearchFocused: Bool

    private var filteredObjects: [S3Object] {
        let query = debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return s3Objects }
        return s3Objects.filter { $0.filename.localizedCaseInsensitiveContains(query) }
    }
    
    // Download/Preview state
    @State private var downloadingObjectKey: String?
    @State private var downloadProgress: Double = 0
    // Tracks files already saved to the download folder this session (object.key -> local URL)
    @State private var localFiles: [String: URL] = [:]
    // Security-scoped folder currently being accessed (kept open so Quick Look can read the file)
    @State private var activeScopedURL: URL?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("BucketDrop")
                    .font(.headline)
                Spacer()
                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gear")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider()
            
            if !settings.isConfigured {
                // Not configured view
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("R2/S3 Not Configured")
                        .font(.headline)
                    Text("Add your R2/S3 credentials in settings to start uploading.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Open Settings") {
                        openSettings()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                // Drop zone
                DropZoneView(
                    isTargeted: $isTargeted,
                    isUploading: isUploading,
                    uploadTasks: uploadTasks
                )
                .onTapGesture {
                    if !isUploading {
                        openFilePicker()
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                    guard !isUploading else { return false }
                    NSApp.activate(ignoringOtherApps: true)
                    handleDrop(providers)
                    return true
                }
                .padding(16)
                
                // Error message
                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            openErrorDetail(errorDetail ?? error)
                        } label: {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Show error details")

                        Button {
                            errorMessage = nil
                            errorDetail = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Dismiss")
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
                
                // Divider()
                
                // Recent uploads
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        Text("Recent Uploads")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if isLoadingList {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button {
                                Task { await loadS3Objects() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .help("Reload")
                        }
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showSearch.toggle()
                            }
                            if showSearch {
                                isSearchFocused = true
                                // Load the full bucket so search covers everything, not just loaded rows
                                Task { await loadAllObjects() }
                            } else {
                                searchText = ""
                                debouncedSearchText = ""
                            }
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(showSearch ? Color.accentColor : Color.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Search all files")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .windowBackgroundColor))

                    if showSearch {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("Search all files", text: $searchText)
                                .textFieldStyle(.plain)
                                .font(.caption)
                                .focused($isSearchFocused)
                            if isLoadingAll {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.7)
                            }
                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: .separatorColor).opacity(0.25))
                        )
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if filteredObjects.isEmpty && !isLoadingList && !isLoadingAll {
                        VStack {
                            Text(debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No files yet" : "No matches")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollViewReader { proxy in
                            List {
                                ForEach(filteredObjects) { object in
                                    FileRowView(
                                        object: object,
                                        previewURL: previewURL(for: object),
                                        isDownloading: downloadingObjectKey == object.key,
                                        downloadProgress: downloadingObjectKey == object.key ? downloadProgress : 0
                                    ) {
                                        copyToClipboard(object)
                                    } onDelete: {
                                        await deleteObject(object)
                                    } onDownload: {
                                        await downloadToDownloads(object)
                                    } onPreview: {
                                        previewFile(object)
                                    }
                                    .id(object.id)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
                                    .onAppear {
                                        // Infinite scroll: load the next page when the last row appears.
                                        // Skipped while searching, where the full bucket is already loaded.
                                        if debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                           object.id == s3Objects.last?.id {
                                            Task { await loadMoreObjects() }
                                        }
                                    }
                                }

                                if isLoadingMore {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                            .controlSize(.small)
                                        Spacer()
                                    }
                                    .listRowInsets(EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6))
                                }
                            }
                            .listStyle(.plain)
                            .scrollIndicators(.never)
                            .onChange(of: filteredObjects.first?.id) { _, newValue in
                                guard let newValue else { return }
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    proxy.scrollTo(newValue, anchor: .top)
                                }
                            }
                        }
                    }
                }
            }
        }
        // .background(Color(nsColor: .textBackgroundColor)) // enable this for bg color
        .frame(width: 320, height: 460)
        .task {
            if settings.isConfigured {
                await loadS3Objects()
            }
        }
        .task(id: searchText) {
            // Debounce search input by 300ms
            do {
                try await Task.sleep(for: .milliseconds(300))
                debouncedSearchText = searchText
            } catch {
                // Task cancelled because searchText changed again; ignore
            }
        }
    }
    
    private func handleDrop(_ providers: [NSItemProvider]) {
        // Collect all file URLs first, then process as a batch
        let lock = NSLock()
        var collectedURLs: [URL] = []
        let group = DispatchGroup()
        
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, error in
                defer { group.leave() }
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                lock.lock()
                collectedURLs.append(url)
                lock.unlock()
            }
        }
        
        group.notify(queue: .main) {
            Task { @MainActor in
                await self.uploadFiles(collectedURLs)
            }
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window) { response in
                guard response == .OK else { return }
                Task { @MainActor in
                    await uploadFiles(panel.urls)
                }
            }
        } else {
            let response = panel.runModal()
            guard response == .OK else { return }
            Task { @MainActor in
                await uploadFiles(panel.urls)
            }
        }
    }
    
    @MainActor
    private func uploadFiles(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        
        // Create upload tasks for all files
        uploadTasks = urls.map { UploadTask(filename: $0.lastPathComponent, url: $0) }
        isUploading = true
        errorMessage = nil
        errorDetail = nil

        var uploadedURLs: [String] = []
        var failureDetails: [String] = []
        
        // Upload files sequentially for clearer progress indication
        for index in uploadTasks.indices {
            uploadTasks[index].status = .uploading
            
            do {
                let fileURL = uploadTasks[index].url
                let result = try await S3Service.shared.upload(fileURL: fileURL) { progress in
                    Task { @MainActor in
                        if index < self.uploadTasks.count {
                            self.uploadTasks[index].progress = progress
                        }
                    }
                }
                
                // Save to local storage
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
                let uploadedFile = UploadedFile(
                    filename: fileURL.lastPathComponent,
                    key: result.key,
                    url: result.url,
                    size: fileSize
                )
                modelContext.insert(uploadedFile)
                
                uploadTasks[index].status = .completed
                uploadTasks[index].progress = 1
                uploadTasks[index].resultURL = result.url
                uploadedURLs.append(result.url)
                
                // Add to list immediately
                let newObject = S3Object(key: result.key, size: fileSize, lastModified: Date())
                s3Objects.insert(newObject, at: 0)
                
            } catch {
                uploadTasks[index].status = .failed(error.localizedDescription)
                let filename = uploadTasks[index].filename
                let sizeText = fileSizeText(for: uploadTasks[index].url)
                failureDetails.append("• \(filename)\(sizeText)\n\(error.localizedDescription)")
            }
        }

        if !failureDetails.isEmpty {
            errorMessage = failureDetails.count == 1
                ? "Upload failed"
                : "\(failureDetails.count) uploads failed"
            errorDetail = failureDetails.joined(separator: "\n\n")
        }

        // Copy all successful URLs to clipboard
        if !uploadedURLs.isEmpty {
            NSPasteboard.general.clearContents()
            if uploadedURLs.count == 1 {
                NSPasteboard.general.setString(uploadedURLs[0], forType: .string)
            } else {
                // Join multiple URLs with newlines
                NSPasteboard.general.setString(uploadedURLs.joined(separator: "\n"), forType: .string)
            }

            // Show a Raycast-style success toast
            let toastMessage = uploadedURLs.count == 1
                ? "Uploaded · link copied"
                : "\(uploadedURLs.count) files uploaded · links copied"
            showToast(toastMessage)
        }
        
        // Reset after delay
        try? await Task.sleep(for: .seconds(2))
        uploadTasks = []
        isUploading = false
    }
    
    private func loadS3Objects() async {
        isLoadingList = true
        do {
            let result = try await S3Service.shared.listObjects()
            s3Objects = result.objects
            nextToken = result.nextToken
            // If a search is active, keep loading the rest in the background
            if !debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Task { await loadAllObjects() }
            }
        } catch {
            setError("Failed to load files", detail: error.localizedDescription)
        }
        isLoadingList = false
    }

    private func loadMoreObjects() async {
        guard !isLoadingMore, !isLoadingAll, let token = nextToken else { return }
        isLoadingMore = true
        do {
            let result = try await S3Service.shared.listObjects(continuationToken: token)
            s3Objects.append(contentsOf: result.objects)
            nextToken = result.nextToken
        } catch {
            setError("Failed to load more files", detail: error.localizedDescription)
        }
        isLoadingMore = false
    }

    /// Loads every remaining page so search can match across the whole bucket.
    private func loadAllObjects() async {
        guard !isLoadingAll, nextToken != nil else { return }
        isLoadingAll = true
        do {
            while let token = nextToken {
                let result = try await S3Service.shared.listObjects(continuationToken: token)
                s3Objects.append(contentsOf: result.objects)
                nextToken = result.nextToken
            }
        } catch {
            setError("Failed to load all files", detail: error.localizedDescription)
        }
        isLoadingAll = false
    }

    private func setError(_ message: String, detail: String) {
        errorMessage = message
        errorDetail = detail
    }

    private func fileSizeText(for url: URL) -> String {
        guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 else {
            return ""
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return " (\(formatter.string(fromByteCount: size)))"
    }
    
    private func copyToClipboard(_ object: S3Object) {
        let url = buildURL(for: object)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }
    
    private func buildURL(for object: S3Object) -> String {
        let encodedKey = awsURLEncodePath(object.key)
        if !settings.publicUrlBase.isEmpty {
            let base = settings.publicUrlBase.hasSuffix("/") ? String(settings.publicUrlBase.dropLast()) : settings.publicUrlBase
            return "\(base)/\(encodedKey)"
        }
        return "https://\(settings.bucket).s3.\(settings.region).amazonaws.com/\(encodedKey)"
    }

    private func previewURL(for object: S3Object) -> URL? {
        guard isImageFile(object.filename) else { return nil }
        return URL(string: buildURL(for: object))
    }

    private func isImageFile(_ filename: String) -> Bool {
        let ext = (filename as NSString).pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "gif", "webp", "svg"].contains(ext)
    }

    private func awsURLEncodePath(_ path: String) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
        return path
            .split(separator: "/")
            .map { segment in
                segment.addingPercentEncoding(withAllowedCharacters: unreserved) ?? String(segment)
            }
            .joined(separator: "/")
    }
    
    private func deleteObject(_ object: S3Object) async {
        do {
            try await S3Service.shared.deleteObject(key: object.key)
            await loadS3Objects()
        } catch {
            setError("Failed to delete file", detail: error.localizedDescription)
        }
    }
    
    // MARK: - Download / Preview

    /// Returns the local URL of the object in the download folder, downloading it there if needed.
    /// Reused by both Download and Preview so a file is fetched only once per session.
    private func ensureLocalFile(for object: S3Object) async throws -> URL {
        // Reuse an already-downloaded file if it still exists
        if let existing = localFiles[object.key], FileManager.default.fileExists(atPath: existing.path) {
            return existing
        }

        guard let (directory, needsStopAccess) = settings.resolveDownloadDirectory() else {
            throw S3Service.S3Error(message: "Could not access the download folder. Pick one in Settings.")
        }

        // Release the previously held scope, then keep this one open so a follow-up
        // Quick Look preview can still read the file from a custom (bookmarked) folder.
        if let previous = activeScopedURL {
            previous.stopAccessingSecurityScopedResource()
            activeScopedURL = nil
        }
        if needsStopAccess {
            activeScopedURL = directory
        }

        downloadingObjectKey = object.key
        downloadProgress = 0
        defer { downloadingObjectKey = nil }

        // Download straight into the configured folder; S3Service picks a unique
        // name when a different file with the same name already exists there.
        let destination = directory.appendingPathComponent(object.filename)
        let finalURL = try await S3Service.shared.download(key: object.key, to: destination, overwrite: false) { progress in
            Task { @MainActor in
                downloadProgress = progress
            }
        }

        localFiles[object.key] = finalURL
        return finalURL
    }

    private func downloadToDownloads(_ object: S3Object) async {
        do {
            let url = try await ensureLocalFile(for: object)
            // Reveal in Finder
            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
        } catch {
            setError("Download failed", detail: error.localizedDescription)
        }
    }

    // MARK: - Preview with Quick Look

    private func previewFile(_ object: S3Object) {
        Task {
            do {
                // Save into the download folder first, then preview from there
                let url = try await ensureLocalFile(for: object)
                await MainActor.run {
                    showQuickLook(for: url)
                }
            } catch {
                await MainActor.run {
                    setError("Preview failed", detail: error.localizedDescription)
                }
            }
        }
    }
    
    private func showQuickLook(for url: URL) {
        // Use QLPreviewPanel for Quick Look
        let coordinator = QuickLookCoordinator()
        coordinator.items = [QuickLookItem(url: url)]
        
        // Store coordinator to keep it alive
        Self.quickLookCoordinator = coordinator
        
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = coordinator
        panel.delegate = coordinator
        panel.currentPreviewItemIndex = 0
        
        if panel.isVisible {
            panel.reloadData()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }
    
    // Static storage for coordinator
    private static var quickLookCoordinator: QuickLookCoordinator?
}

struct DropZoneView: View {
    @Binding var isTargeted: Bool
    let isUploading: Bool
    let uploadTasks: [UploadTask]
    
    private var completedCount: Int {
        uploadTasks.filter { 
            if case .completed = $0.status { return true }
            return false
        }.count
    }
    
    private var totalCount: Int {
        uploadTasks.count
    }
    
    private var overallProgress: Double {
        guard !uploadTasks.isEmpty else { return 0 }
        return uploadTasks.reduce(0) { $0 + $1.progress } / Double(uploadTasks.count)
    }
    
    private var currentlyUploading: UploadTask? {
        uploadTasks.first { 
            if case .uploading = $0.status { return true }
            return false
        }
    }
    
    private var allCompleted: Bool {
        completedCount == totalCount && totalCount > 0
    }
    
    var body: some View {
        VStack(spacing: 8) {
            if isUploading {
                if allCompleted {
                    // All done state
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(nsColor: .systemGreen))
                    if totalCount == 1 {
                        Text("Copied to clipboard!")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(totalCount) URLs copied to clipboard!")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    // Progress state
                    VStack(spacing: 6) {
                        ProgressView(value: overallProgress)
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 220)
                        
                        // Status text
                        if totalCount == 1 {
                            Text("Uploading \(currentlyUploading?.filename ?? "")...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text("Uploading \(completedCount + 1) of \(totalCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let current = currentlyUploading {
                                Text(current.filename)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            } else {
                Image(systemName: isTargeted ? "arrow.down.circle.fill" : "arrow.up.circle")
                    .font(.system(size: 24))
                    .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                Text(isTargeted ? "Drop to upload" : "Drop files here or click to select")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color(nsColor: .quaternaryLabelColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color(nsColor: .separatorColor),
                    lineWidth: isTargeted ? 2 : 1
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }
}

// Custom progress style that doesn't gray out when window loses focus
struct ActiveProgressViewStyle: ProgressViewStyle {
    var height: CGFloat = 12
    
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            let progress = configuration.fractionCompleted ?? 0
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(nsColor: .separatorColor).opacity(0.3))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * progress)
                    .animation(.easeOut(duration: 0.15), value: progress)
            }
        }
        .frame(height: height)
    }
}

enum CachedImageState {
    case loading
    case success(Image)
    case failure
}

final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, NSImage>()
    
    func image(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }
    
    func insert(_ image: NSImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}

final class ImageLoader: ObservableObject {
    @Published var state: CachedImageState = .loading
    private var task: Task<Void, Never>?
    
    func load(from url: URL) {
        if let cached = ImageCache.shared.image(for: url) {
            state = .success(Image(nsImage: cached))
            return
        }
        
        task?.cancel()
        task = Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = NSImage(data: data) else {
                    await MainActor.run { self.state = .failure }
                    return
                }
                ImageCache.shared.insert(image, for: url)
                await MainActor.run { self.state = .success(Image(nsImage: image)) }
            } catch {
                await MainActor.run { self.state = .failure }
            }
        }
    }
    
    func cancel() {
        task?.cancel()
        task = nil
    }
}

struct CachedAsyncImage<Content: View>: View {
    let url: URL
    @ViewBuilder let content: (CachedImageState) -> Content
    @StateObject private var loader = ImageLoader()
    
    var body: some View {
        content(loader.state)
            .onAppear { loader.load(from: url) }
            .onChange(of: url) { _, newURL in
                loader.load(from: newURL)
            }
            .onDisappear { loader.cancel() }
    }
}

struct FileRowView: View {
    let object: S3Object
    let previewURL: URL?
    let isDownloading: Bool
    let downloadProgress: Double
    let onCopy: () -> Void
    let onDelete: () async -> Void
    let onDownload: () async -> Void
    let onPreview: () -> Void
    
    @State private var isHovered = false
    @State private var isDeleting = false
    @State private var isCopied = false
    
    var body: some View {
        HStack(spacing: 10) {
            // Thumbnail
            if let previewURL {
                CachedAsyncImage(url: previewURL) { state in
                    switch state {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    case .loading:
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
                )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: .separatorColor).opacity(0.3))
                    Image(systemName: iconForFile(object.filename))
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 32, height: 32)
            }
            
            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(object.filename)
                    .font(.system(.subheadline).weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                // Show progress bar OR file size
                if isDownloading {
                    ProgressView(value: downloadProgress)
                        .progressViewStyle(ActiveProgressViewStyle(height: 6))
                        .padding(.top, 2)
                } else {
                    Text(formatSize(object.size))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer(minLength: 8)
            
            // Action buttons - always in layout, opacity controlled by hover
            HStack(spacing: 6) {
                // Copy URL stays as a dedicated button
                Button {
                    if !isDeleting && !isDownloading {
                        onCopy()
                        Task { @MainActor in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isCopied = true
                            }
                            try? await Task.sleep(for: .seconds(1))
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isCopied = false
                            }
                        }
                    }
                } label: {
                    Image(systemName: isCopied ? "checkmark.circle.fill" : "link")
                        .foregroundStyle(isCopied ? Color.green : Color.secondary)
                }
                .buttonStyle(.borderless)
                .help("Copy link")
                .disabled(isDeleting || isDownloading)

                // Other actions collapsed into a 3-dots dropdown menu
                if isDeleting {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 20)
                } else {
                    Menu {
                        Button {
                            Task { await onDownload() }
                        } label: {
                            Label("Download", systemImage: "arrow.down.circle")
                        }
                        Button {
                            onPreview()
                        } label: {
                            Label("Preview", systemImage: "eye")
                        }
                        Divider()
                        Button(role: .destructive) {
                            Task {
                                isDeleting = true
                                await onDelete()
                                isDeleting = false
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(Color.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .frame(width: 20)
                    .help("More actions")
                    .disabled(isDownloading)
                }
            }
            .opacity(isHovered || isDeleting || isDownloading ? 1 : 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) {
            if !isDownloading {
                onPreview()
            }
        }
    }
    
    private func iconForFile(_ filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "webp", "svg":
            return "photo"
        case "mp4", "mov", "avi":
            return "video"
        case "mp3", "wav", "m4a":
            return "music.note"
        case "pdf":
            return "doc.richtext"
        case "zip", "rar", "7z":
            return "archivebox"
        default:
            return "doc"
        }
    }
    
    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Quick Look Support

class QuickLookItem: NSObject, QLPreviewItem {
    let url: URL
    
    init(url: URL) {
        self.url = url
        super.init()
    }
    
    var previewItemURL: URL? { url }
    var previewItemTitle: String? { url.lastPathComponent }
}

class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    var items: [QuickLookItem] = []
    
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        items.count
    }
    
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard index < items.count else { return nil }
        return items[index]
    }
}

#Preview {
    ContentView()
        .modelContainer(for: UploadedFile.self, inMemory: true)
}
