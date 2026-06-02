//
//  ShellProfile.swift
//  Reynard
//
//  Runtime profile selected by the app configuration.
//

import Foundation

struct ShellProfile {
    let target: ShellTarget
    let displayName: String
    let defaultURL: URL?
    let features: ShellFeatures
}
