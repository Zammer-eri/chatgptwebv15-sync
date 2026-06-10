//
//  ShellProfile.swift
//  Reynard
//
//  Runtime profile selected by the app configuration.
//

import Foundation

enum ShellUserAgentPolicy: Equatable {
    case configurable
    case androidMobile
}

struct ShellProfile {
    let target: ShellTarget
    let displayName: String
    let defaultURL: URL?
    let features: ShellFeatures
    let userAgentPolicy: ShellUserAgentPolicy
}
