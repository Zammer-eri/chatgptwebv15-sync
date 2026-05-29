//
//  GeckoSession.swift
//  Reynard
//
//  Created by Minh Ton on 1/2/26.
//

import UIKit

protocol GeckoSessionHandlerCommon: GeckoEventListenerInternal {
    var moduleName: String { get }
    var events: [String] { get }
    var enabled: Bool { get }
}

public struct GeckoSessionSettings {
    public let userAgentOverride: String?
    public let userAgentMode: Int
    public let viewportMode: Int

    public init(userAgentOverride: String?, userAgentMode: Int, viewportMode: Int) {
        self.userAgentOverride = userAgentOverride
        self.userAgentMode = userAgentMode
        self.viewportMode = viewportMode
    }
}

public enum GeckoSessionLoadFlags {
    public static let none = 0
    public static let bypassCache = 1 << 0
    public static let replaceHistory = 1 << 6
}

public class GeckoSession {
    let dispatcher: GeckoEventDispatcherWrapper = GeckoEventDispatcherWrapper()
    var window: GeckoViewWindow?
    var id: String?
    public var userAgentOverride: String?
    public var userAgentMode = 0
    public var viewportMode = 0

    public func updateUserAgent(_ ua: String?) {
        updateSettings(
            GeckoSessionSettings(
                userAgentOverride: ua,
                userAgentMode: userAgentMode,
                viewportMode: viewportMode
            )
        )
    }

    public func updateSettings(_ settings: GeckoSessionSettings) {
        userAgentOverride = settings.userAgentOverride
        userAgentMode = settings.userAgentMode
        viewportMode = settings.viewportMode

        guard isOpen() else { return }
        let uaValue: Any = settings.userAgentOverride ?? NSNull()
        dispatcher.dispatch(
            type: "GeckoView:UpdateSettings",
            message: [
                "userAgentOverride": uaValue,
                "userAgentMode": settings.userAgentMode,
                "viewportMode": settings.viewportMode,
            ])
    }

    lazy var contentHandler = newContentHandler(self)
    lazy var processHangHandler = newProcessHangHandler(self)
    public var contentDelegate: ContentDelegate? {
        get { contentHandler.delegate(as: ContentDelegate.self) }
        set {
            contentHandler.setDelegate(newValue)
            processHangHandler.setDelegate(newValue)
        }
    }

    lazy var navigationHandler = newNavigationHandler(self)
    public var navigationDelegate: NavigationDelegate? {
        get { navigationHandler.delegate(as: NavigationDelegate.self) }
        set { navigationHandler.setDelegate(newValue) }
    }

    lazy var progressHandler = newProgressHandler(self)
    public var progressDelegate: ProgressDelegate? {
        get { progressHandler.delegate(as: ProgressDelegate.self) }
        set { progressHandler.setDelegate(newValue) }
    }

    lazy var promptHandler: GeckoSessionHandler = {
        let handler = newPromptHandler(self)
        handler.setDelegate(true as AnyObject)
        return handler
    }()

    public lazy var mediaSession = MediaSession(session: self)

    lazy var sessionHandlers: [GeckoSessionHandlerCommon] = [
        contentHandler,
        processHangHandler,
        navigationHandler,
        progressHandler,
        promptHandler,
    ]

    public init() {
        for sessionHandler in sessionHandlers {
            for type in sessionHandler.events {
                dispatcher.addListener(type: type, listener: sessionHandler)
            }
        }
    }

    public func open(windowId: String? = nil) {
        if isOpen() {
            fatalError("cannot open a GeckoSession twice")
        }

        let sessionID = windowId ?? UUID().uuidString.replacingOccurrences(of: "-", with: "")
        id = sessionID

        let settings: [String: Any] = [
            "chromeUri": NSNull(),
            "screenId": 0,
            "useTrackingProtection": false,
            "userAgentMode": userAgentMode,
            "userAgentOverride": userAgentOverride ?? NSNull(),
            "viewportMode": viewportMode,
            "displayMode": 0,
            "suspendMediaWhenInactive": false,
            "allowJavascript": true,
            "fullAccessibilityTree": false,
            "isExtensionPopup": false,
            "sessionContextId": NSNull(),
            "unsafeSessionContextId": NSNull(),
        ]

        let modules = Dictionary(uniqueKeysWithValues: sessionHandlers.map {
            ($0.moduleName, $0.enabled)
        })

        window = GeckoViewOpenWindow(
            sessionID,
            dispatcher,
            [
                "settings": settings,
                "modules": modules,
            ],
            false
        )
    }

    public func isOpen() -> Bool { window != nil }

    public func close() {
        guard let window else {
            return
        }

        contentDelegate = nil
        navigationDelegate = nil
        progressDelegate = nil

        window.close()
        self.window = nil
        id = nil
    }

    public func load(_ url: String, flags: Int = GeckoSessionLoadFlags.none) {
        dispatchLoad(url, flags: flags)
    }

    private func dispatchLoad(_ url: String, flags: Int) {
        dispatcher.dispatch(
            type: "GeckoView:LoadUri",
            message: [
                "uri": url,
                "flags": flags,
                "headerFilter": 1,
            ])
    }

    public func reload(flags: Int = GeckoSessionLoadFlags.none) {
        dispatcher.dispatch(
            type: "GeckoView:Reload",
            message: [
                "flags": flags
            ])
    }

    public func stop() {
        dispatcher.dispatch(type: "GeckoView:Stop")
    }

    public func goBack(userInteraction: Bool = true) {
        dispatcher.dispatch(
            type: "GeckoView:GoBack",
            message: [
                "userInteraction": userInteraction
            ])
    }

    public func goForward(userInteraction: Bool = true) {
        dispatcher.dispatch(
            type: "GeckoView:GoForward",
            message: [
                "userInteraction": userInteraction
            ])
    }

    public func setActive(_ active: Bool) {
        dispatcher.dispatch(type: "GeckoView:SetActive", message: ["active": active])
    }

    public func setFocused(_ focused: Bool) {
        dispatcher.dispatch(type: "GeckoView:SetFocused", message: ["focused": focused])
    }
}
