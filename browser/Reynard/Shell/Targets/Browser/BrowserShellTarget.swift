//
//  BrowserShellTarget.swift
//  Reynard
//
//  Upstream-style browser profile.
//

enum BrowserShellTarget {
    static let profile = ShellProfile(
        target: .browser,
        displayName: "Browser",
        defaultURL: nil,
        features: .browser
    )
}
