//
//  AppUpdates.swift
//  Reynard
//
//  Created by Minh Ton on 21/4/26.
//

import Foundation

final class AppUpdates: NSObject {
    static let shared = AppUpdates()
    
    private(set) var hasUpdate: Bool = false
    private(set) var latestVersion: String = ""
    private(set) var sourceData: Data?
    var cachedReleaseNotes: NSAttributedString?
    
    static let updateAvailableNotification = Notification.Name("me.minh-ton.reynard.update-available")
    
    private override init() {
        super.init()
        
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let sideloadIPA = docs.appendingPathComponent("ChatGPT.ipa")
        let trollstoreTIPA = docs.appendingPathComponent("ChatGPT-TrollStore.tipa")
        try? FileManager.default.removeItem(at: sideloadIPA)
        try? FileManager.default.removeItem(at: trollstoreTIPA)
        
        // Private ChatGPT shell builds update through GitHub Actions artifacts.
    }
    
}
