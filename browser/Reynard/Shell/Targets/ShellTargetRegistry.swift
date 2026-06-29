//
//  ShellTargetRegistry.swift
//  Reynard
//
//  Maps shell identifiers to runtime profiles.
//

enum ShellTargetRegistry {
    static func profile(for target: ShellTarget) -> ShellProfile {
        switch target {
        case .browser:
            return BrowserShellTarget.profile
        case .chatGPT:
            return ChatGPTShellTarget.profile
        }
    }
}
