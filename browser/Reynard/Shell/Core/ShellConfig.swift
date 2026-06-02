//
//  ShellConfig.swift
//  Reynard
//
//  Runtime entrypoint for the selected shell profile.
//

import Foundation

enum ShellConfig {
    static let current = ShellTargetRegistry.profile(for: selectedTarget)
    static let urlScheme = stringValue(forInfoDictionaryKey: "ShellURLScheme", defaultValue: "reynard").lowercased()

    private static var selectedTarget: ShellTarget {
        let normalizedValue = stringValue(forInfoDictionaryKey: "ShellTarget", defaultValue: "browser").lowercased()
        return ShellTarget(rawValue: normalizedValue) ?? .browser
    }

    private static func stringValue(forInfoDictionaryKey key: String, defaultValue: String) -> String {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return defaultValue
        }

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty || trimmedValue.hasPrefix("$(") ? defaultValue : trimmedValue
    }
}
