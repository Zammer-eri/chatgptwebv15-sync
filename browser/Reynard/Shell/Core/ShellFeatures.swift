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
    let prefersMobileUserAgent: Bool
    let requiresLocation: Bool

    static let browser = ShellFeatures(
        restoresPreviousTabs: true,
        loadDefaultURLOnFirstLaunch: false,
        allowsSiteJavaScript: false,
        hidesBrowserChrome: false,
        visuallyHidesBrowserChrome: false,
        visualChromePhoneBottomHeight: nil,
        usesShellGestures: false,
        usesUtilityPanel: false,
        prefersMobileUserAgent: false,
        requiresLocation: false
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
        prefersMobileUserAgent: false,
        requiresLocation: false
    )
}
