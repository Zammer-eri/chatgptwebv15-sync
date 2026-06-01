//
//  ShellConfig.swift
//  Reynard
//
//  Central shell target configuration. Keep target behavior opt-in so the
//  proven browser baseline stays unchanged unless a build selects a shell.
//

import Foundation

enum ShellTarget: String {
    case browser
    case chatGPT = "chatgpt"
    case uber
}

struct ShellFeatures {
    let restoresPreviousTabs: Bool
    let loadDefaultURLOnFirstLaunch: Bool
    let allowsSiteJavaScript: Bool
    let hidesBrowserChrome: Bool
    let prefersMobileUserAgent: Bool
    let requiresLocation: Bool

    static let browser = ShellFeatures(
        restoresPreviousTabs: true,
        loadDefaultURLOnFirstLaunch: false,
        allowsSiteJavaScript: false,
        hidesBrowserChrome: false,
        prefersMobileUserAgent: false,
        requiresLocation: false
    )

    static let webApp = ShellFeatures(
        restoresPreviousTabs: false,
        loadDefaultURLOnFirstLaunch: true,
        allowsSiteJavaScript: false,
        hidesBrowserChrome: true,
        prefersMobileUserAgent: false,
        requiresLocation: false
    )
}

struct ShellProfile {
    let target: ShellTarget
    let displayName: String
    let defaultURL: URL?
    let features: ShellFeatures
}

enum ShellConfig {
    static let current = profile(for: selectedTarget)
    static let urlScheme = stringValue(forInfoDictionaryKey: "ShellURLScheme", defaultValue: "chatgptshell").lowercased()

    private static var selectedTarget: ShellTarget {
        let normalizedValue = stringValue(forInfoDictionaryKey: "ShellTarget", defaultValue: "chatgpt").lowercased()
        return ShellTarget(rawValue: normalizedValue) ?? .browser
    }

    private static func stringValue(forInfoDictionaryKey key: String, defaultValue: String) -> String {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return defaultValue
        }

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty || trimmedValue.hasPrefix("$(") ? defaultValue : trimmedValue
    }

    private static func profile(for target: ShellTarget) -> ShellProfile {
        switch target {
        case .browser:
            return ShellProfile(
                target: .browser,
                displayName: "Browser",
                defaultURL: nil,
                features: .browser
            )
        case .chatGPT:
            return ShellProfile(
                target: .chatGPT,
                displayName: "ChatGPT",
                defaultURL: URL(string: "https://chatgpt.com"),
                features: .webApp
            )
        case .uber:
            return ShellProfile(
                target: .uber,
                displayName: "Uber",
                defaultURL: URL(string: "https://m.uber.com"),
                features: .webApp
            )
        }
    }
}
