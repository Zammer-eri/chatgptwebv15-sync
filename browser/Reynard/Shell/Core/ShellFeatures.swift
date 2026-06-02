//
//  ShellFeatures.swift
//  Reynard
//
//  Reusable shell capabilities.
//

struct ShellFeatures {
    let restoresPreviousTabs: Bool
    let loadDefaultURLOnFirstLaunch: Bool
    let allowsSiteJavaScript: Bool
    let hidesBrowserChrome: Bool
    let visuallyHidesBrowserChrome: Bool
    let visualChromePhoneBottomHeight: Int?
    let usesShellGestures: Bool
    let usesUtilityPanel: Bool
    let usesSingleTabSession: Bool
    let prefersMobileUserAgent: Bool
    let requiresLocation: Bool
    let checksForAppUpdates: Bool
    let runsAutomaticAddonUpdates: Bool
    let recordsBrowsingHistory: Bool
    let loadsFavicons: Bool

    static let browser = ShellFeatures(
        restoresPreviousTabs: true,
        loadDefaultURLOnFirstLaunch: false,
        allowsSiteJavaScript: false,
        hidesBrowserChrome: false,
        visuallyHidesBrowserChrome: false,
        visualChromePhoneBottomHeight: nil,
        usesShellGestures: false,
        usesUtilityPanel: false,
        usesSingleTabSession: false,
        prefersMobileUserAgent: false,
        requiresLocation: false,
        checksForAppUpdates: true,
        runsAutomaticAddonUpdates: true,
        recordsBrowsingHistory: true,
        loadsFavicons: true
    )

    static let webApp = ShellFeatures(
        restoresPreviousTabs: false,
        loadDefaultURLOnFirstLaunch: true,
        allowsSiteJavaScript: false,
        hidesBrowserChrome: false,
        visuallyHidesBrowserChrome: true,
        visualChromePhoneBottomHeight: 0,
        usesShellGestures: true,
        usesUtilityPanel: true,
        usesSingleTabSession: true,
        prefersMobileUserAgent: false,
        requiresLocation: false,
        checksForAppUpdates: false,
        runsAutomaticAddonUpdates: false,
        recordsBrowsingHistory: false,
        loadsFavicons: false
    )
}
