//
//  UserAgentController.swift
//  Reynard
//
//  Created by Minh Ton on 21/4/26.
//

import Foundation
import GeckoView

final class UserAgentController {
    static let shared = UserAgentController()

    private enum SessionMode {
        static let mobile = 0
    }

    private init() {}

    func userAgent(for urlString: String) -> String? {
        userAgent(for: urlString, tabID: nil)
    }

    func userAgent(for urlString: String, tabID: UUID?) -> String? {
        sessionSettings(for: urlString, tabID: tabID).userAgentOverride
    }

    func sessionSettings(for urlString: String, tabID: UUID?) -> GeckoSessionSettings {
        let geckoVersion = Bundle.main.object(forInfoDictionaryKey: "GeckoVersion") as? String ?? ""
        let geckoMajorVersion = geckoVersion.split(whereSeparator: { !$0.isNumber }).first.map(String.init) ?? "0"
        let androidMobileUserAgent = "Mozilla/5.0 (Android 15; Mobile; rv:\(geckoMajorVersion).0) Gecko/\(geckoMajorVersion).0 Firefox/\(geckoMajorVersion).0"

        return GeckoSessionSettings(
            userAgentOverride: BrowserPreferences.shared.useAndroidUserAgent ? androidMobileUserAgent : nil,
            userAgentMode: SessionMode.mobile,
            viewportMode: SessionMode.mobile
        )
    }

    func clearOverrides(forTabID tabID: UUID) {
    }

    func extractHost(from urlString: String) -> String? {
        if let host = URL(string: urlString)?.host?.lowercased() {
            return host
        }

        if let host = URL(string: "https://" + urlString)?.host?.lowercased() {
            return host
        }

        return nil
    }
}
