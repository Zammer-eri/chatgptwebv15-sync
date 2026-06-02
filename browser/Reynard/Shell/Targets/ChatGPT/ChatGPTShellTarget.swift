//
//  ChatGPTShellTarget.swift
//  Reynard
//
//  ChatGPT shell profile.
//

import Foundation

enum ChatGPTShellTarget {
    static let profile = ShellProfile(
        target: .chatGPT,
        displayName: "ChatGPT",
        defaultURL: URL(string: "https://chatgpt.com"),
        features: .webApp
    )
}
