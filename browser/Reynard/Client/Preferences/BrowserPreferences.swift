//
//  BrowserPreferences.swift
//  Reynard
//
//  Created by Minh Ton on 10/3/26.
//

import Foundation
import UIKit

final class BrowserPreferences {
    private enum Keys {
        static let jitEnabled = "BrowserPreferences.jitEnabled"
        static let useAndroidUserAgent = "BrowserPreferences.useAndroidUserAgent"
        static let timeAwareEnabled = "BrowserPreferences.timeAwareEnabled"
        static let timeAwareTimezone = "BrowserPreferences.timeAwareTimezone"
    }
    
    static let shared = BrowserPreferences()
    
    private let defaults: UserDefaults
    private let fileManager: FileManager
    
    init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.defaults = defaults
        self.fileManager = fileManager
        registerDefaults()
    }
    
    var hasPairingFile: Bool {
        fileManager.fileExists(atPath: pairingFileURL.path)
    }
    
    var isJITEnabled: Bool {
        get {
            guard hasPairingFile else {
                return false
            }
            return defaults.bool(forKey: Keys.jitEnabled)
        }
        set {
            defaults.set(hasPairingFile && newValue, forKey: Keys.jitEnabled)
        }
    }

    var useAndroidUserAgent: Bool {
        get { defaults.bool(forKey: Keys.useAndroidUserAgent) }
        set { defaults.set(newValue, forKey: Keys.useAndroidUserAgent) }
    }

    var timeAwareEnabled: Bool {
        get { defaults.bool(forKey: Keys.timeAwareEnabled) }
        set { defaults.set(newValue, forKey: Keys.timeAwareEnabled) }
    }

    var timeAwareTimezone: String {
        get { defaults.string(forKey: Keys.timeAwareTimezone) ?? "Europe/Paris" }
        set { defaults.set(newValue, forKey: Keys.timeAwareTimezone) }
    }
    
    var pairingFileURL: URL {
        documentsDirectory.appendingPathComponent("pairingFile.plist", isDirectory: false)
    }
    
    func installPairingFile(from sourceURL: URL) throws {
        let destinationURL = pairingFileURL
        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        
        let normalizedSourceURL = sourceURL.standardizedFileURL
        let normalizedDestinationURL = destinationURL.standardizedFileURL
        
        guard normalizedSourceURL != normalizedDestinationURL else {
            isJITEnabled = false
            return
        }
        
        if fileManager.fileExists(atPath: normalizedDestinationURL.path) {
            try fileManager.removeItem(at: normalizedDestinationURL)
        }
        
        try fileManager.copyItem(at: normalizedSourceURL, to: normalizedDestinationURL)
        isJITEnabled = false
    }
    
    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    private func registerDefaults() {
        defaults.register(defaults: [
            Keys.jitEnabled: false,
            Keys.useAndroidUserAgent: true,
            Keys.timeAwareEnabled: true,
            Keys.timeAwareTimezone: "Europe/Paris",
        ])
    }
}
