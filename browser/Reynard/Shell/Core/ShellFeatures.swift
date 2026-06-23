//
//  ShellFeatures.swift
//  Reynard
//
//  Reusable shell capabilities.
//

struct ShellFeatures {
    let restoresPreviousTabs: Bool
    let loadDefaultURLOnFirstLaunch: Bool
    let visuallyHidesBrowserChrome: Bool
    let visualChromePhoneBottomHeight: Int?
    let usesShellGestures: Bool
    let usesUtilityPanel: Bool
    let usesSingleTabSession: Bool
    let requiresLocation: Bool
    let checksForAppUpdates: Bool
    let usesAddons: Bool
    let runsAutomaticAddonUpdates: Bool
    let recordsBrowsingHistory: Bool
    let loadsFavicons: Bool

    static let browser = ShellFeatures(
        restoresPreviousTabs: true,
        loadDefaultURLOnFirstLaunch: false,
        visuallyHidesBrowserChrome: false,
        visualChromePhoneBottomHeight: nil,
        usesShellGestures: false,
        usesUtilityPanel: false,
        usesSingleTabSession: false,
        requiresLocation: false,
        checksForAppUpdates: true,
        usesAddons: true,
        runsAutomaticAddonUpdates: true,
        recordsBrowsingHistory: true,
        loadsFavicons: true
    )

    static func webApp(visualChromePhoneBottomHeight: Int = 0) -> ShellFeatures {
        ShellFeatures(
            restoresPreviousTabs: false,
            loadDefaultURLOnFirstLaunch: true,
            visuallyHidesBrowserChrome: true,
            visualChromePhoneBottomHeight: visualChromePhoneBottomHeight,
            usesShellGestures: true,
            usesUtilityPanel: true,
            usesSingleTabSession: true,
            requiresLocation: false,
            checksForAppUpdates: false,
            usesAddons: false,
            runsAutomaticAddonUpdates: false,
            recordsBrowsingHistory: false,
            loadsFavicons: false
        )
    }
}
