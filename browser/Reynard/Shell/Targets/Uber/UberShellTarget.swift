//
//  UberShellTarget.swift
//  Reynard
//
//  Uber shell profile.
//

import Foundation

enum UberShellTarget {
    static let profile = ShellProfile(
        target: .uber,
        displayName: "Uber",
        defaultURL: URL(string: "https://m.uber.com"),
        features: .webApp
    )
}
