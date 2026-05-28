//
//  ChatGPTWebsiteDataCleaner.swift
//  Reynard
//

import Foundation

enum ChatGPTWebsiteDataCleaner {
    private static let purgeVersion = "chatgpt-v36"
    private static let purgeDefaultsKey = "ChatGPTWebsiteDataCleaner.purgeVersion"

    private static let originNeedles = [
        "chatgpt.com",
        "chat.openai.com",
        "openai.com",
        "oaistatic.com",
        "oaiusercontent.com"
    ]

    private static let originCacheDirectoryNames: Set<String> = [
        "cache",
        "cache2"
    ]

    private static let serviceWorkerFileNames: Set<String> = [
        "serviceworker.txt",
        "serviceworker.txt.tmp"
    ]

    static func clearStaleLaunchCachesIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: purgeDefaultsKey) != purgeVersion else {
            return
        }

        clearLaunchCaches()
        defaults.set(purgeVersion, forKey: purgeDefaultsKey)
    }

    private static func clearLaunchCaches() {
        let fileManager = FileManager.default
        let homeURL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let libraryURL = homeURL.appendingPathComponent("Library", isDirectory: true)
        guard fileManager.fileExists(atPath: libraryURL.path) else {
            return
        }

        var removedCount = 0
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
        guard let enumerator = fileManager.enumerator(
            at: libraryURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return
        }

        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let name = url.lastPathComponent.lowercased()
            let path = url.path.lowercased()

            if values?.isDirectory == true {
                if shouldRemoveDirectory(name: name, path: path) {
                    removedCount += removeItem(at: url, fileManager: fileManager)
                    enumerator.skipDescendants()
                }
                continue
            }

            if values?.isRegularFile == true, shouldRemoveFile(name: name, path: path) {
                removedCount += removeItem(at: url, fileManager: fileManager)
            }
        }

        if removedCount > 0 {
            NSLog("ChatGPTWebsiteDataCleaner removed \(removedCount) cache item(s)")
        }
    }

    private static func shouldRemoveDirectory(name: String, path: String) -> Bool {
        guard originCacheDirectoryNames.contains(name),
              originNeedles.contains(where: { path.contains($0) }) else {
            return false
        }

        return path.contains("/storage/") || path.contains("\\storage\\")
    }

    private static func shouldRemoveFile(name: String, path: String) -> Bool {
        if serviceWorkerFileNames.contains(name) {
            return true
        }

        guard originNeedles.contains(where: { path.contains($0) }) else {
            return false
        }

        return name.contains("cachestorage") || name.contains("serviceworker")
    }

    private static func removeItem(at url: URL, fileManager: FileManager) -> Int {
        do {
            try fileManager.removeItem(at: url)
            return 1
        } catch {
            NSLog("ChatGPTWebsiteDataCleaner failed to remove \(url.path): \(error)")
            return 0
        }
    }
}
