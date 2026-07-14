//
//  SettingsManager.swift
//  BucketDrop
//
//  Created by Fayaz Ahmed Aralikatti on 12/01/26.
//

import Foundation
import Security

@Observable
final class SettingsManager {
    static let shared = SettingsManager()
    
    private let defaults = UserDefaults.standard
    
    private enum Keys {
        static let accessKeyId = "s3_access_key_id"
        static let secretAccessKey = "s3_secret_access_key"
        static let bucket = "s3_bucket"
        static let region = "s3_region"
        static let endpoint = "s3_endpoint"
        static let publicUrlBase = "s3_public_url_base"
        static let folderPrefix = "s3_folder_prefix"
        static let downloadBookmark = "download_directory_bookmark"
    }
    
    // Stored properties for observation
    private(set) var _accessKeyId: String = ""
    private(set) var _secretAccessKey: String = ""
    private(set) var _bucket: String = ""
    private(set) var _region: String = "us-east-1"
    private(set) var _endpoint: String = ""
    private(set) var _publicUrlBase: String = ""
    private(set) var _folderPrefix: String = ""
    
    var accessKeyId: String {
        get { _accessKeyId }
        set {
            _accessKeyId = newValue
            setKeychainItem(key: Keys.accessKeyId, value: newValue)
        }
    }
    
    var secretAccessKey: String {
        get { _secretAccessKey }
        set {
            _secretAccessKey = newValue
            setKeychainItem(key: Keys.secretAccessKey, value: newValue)
        }
    }
    
    var bucket: String {
        get { _bucket }
        set {
            _bucket = newValue
            defaults.set(newValue, forKey: Keys.bucket)
        }
    }
    
    var region: String {
        get { _region }
        set {
            _region = newValue
            defaults.set(newValue, forKey: Keys.region)
        }
    }
    
    var endpoint: String {
        get { _endpoint }
        set {
            _endpoint = newValue
            defaults.set(newValue, forKey: Keys.endpoint)
        }
    }
    
    var publicUrlBase: String {
        get { _publicUrlBase }
        set {
            _publicUrlBase = newValue
            defaults.set(newValue, forKey: Keys.publicUrlBase)
        }
    }

    var folderPrefix: String {
        get { _folderPrefix }
        set {
            _folderPrefix = newValue
            defaults.set(newValue, forKey: Keys.folderPrefix)
        }
    }
    
    var isConfigured: Bool {
        !_accessKeyId.isEmpty && !_secretAccessKey.isEmpty && !_bucket.isEmpty
    }

    // MARK: - Download destination

    /// Observed display name for the current download folder (updates the settings UI).
    private(set) var downloadDirectoryDisplayName: String = "Downloads"

    /// True when the user has picked a custom folder (i.e. not the default Downloads).
    var hasCustomDownloadDirectory: Bool {
        defaults.data(forKey: Keys.downloadBookmark) != nil
    }

    /// The default Downloads folder (accessible via the downloads entitlement).
    private var defaultDownloadDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }

    /// Persist a user-picked folder as a security-scoped bookmark.
    func setDownloadDirectory(_ url: URL) {
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            defaults.set(bookmark, forKey: Keys.downloadBookmark)
        } catch {
            defaults.removeObject(forKey: Keys.downloadBookmark)
        }
        refreshDownloadDirectoryDisplayName()
    }

    /// Revert to the default Downloads folder.
    func resetDownloadDirectory() {
        defaults.removeObject(forKey: Keys.downloadBookmark)
        refreshDownloadDirectoryDisplayName()
    }

    /// Resolves the destination folder for downloads.
    /// - Returns: the folder URL and whether the caller must call
    ///   `stopAccessingSecurityScopedResource()` when finished.
    func resolveDownloadDirectory() -> (url: URL, needsStopAccess: Bool)? {
        guard let bookmark = defaults.data(forKey: Keys.downloadBookmark) else {
            return (defaultDownloadDirectory, false)
        }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            // Bookmark no longer resolvable; fall back to Downloads
            return (defaultDownloadDirectory, false)
        }

        if isStale {
            // Refresh the stored bookmark opportunistically
            if let refreshed = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                defaults.set(refreshed, forKey: Keys.downloadBookmark)
            }
        }

        let didStart = url.startAccessingSecurityScopedResource()
        return (url, didStart)
    }

    private func refreshDownloadDirectoryDisplayName() {
        guard let bookmark = defaults.data(forKey: Keys.downloadBookmark) else {
            downloadDirectoryDisplayName = defaultDownloadDirectory.lastPathComponent
            return
        }
        var isStale = false
        if let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
            downloadDirectoryDisplayName = url.lastPathComponent
        } else {
            downloadDirectoryDisplayName = defaultDownloadDirectory.lastPathComponent
        }
    }

    private init() {
        // Load initial values from storage
        _accessKeyId = getKeychainItem(key: Keys.accessKeyId) ?? ""
        _secretAccessKey = getKeychainItem(key: Keys.secretAccessKey) ?? ""
        _bucket = defaults.string(forKey: Keys.bucket) ?? ""
        _region = defaults.string(forKey: Keys.region) ?? "us-east-1"
        _endpoint = defaults.string(forKey: Keys.endpoint) ?? ""
        _publicUrlBase = defaults.string(forKey: Keys.publicUrlBase) ?? ""
        _folderPrefix = defaults.string(forKey: Keys.folderPrefix) ?? ""
        refreshDownloadDirectoryDisplayName()
    }
    
    // MARK: - Keychain
    
    private func setKeychainItem(key: String, value: String) {
        let data = value.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.fayazahmed.BucketDrop"
        ]
        
        SecItemDelete(query as CFDictionary)
        
        var newQuery = query
        newQuery[kSecValueData as String] = data
        SecItemAdd(newQuery as CFDictionary, nil)
    }
    
    private func getKeychainItem(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.fayazahmed.BucketDrop",
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        
        return String(data: data, encoding: .utf8)
    }
}
