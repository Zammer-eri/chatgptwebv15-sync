//
//  TabManagerImpl.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import Foundation
import GeckoView
import UIKit

final class TabManagerImplementation: NSObject, TabManager {
    private static let shellHomeURL = "https://chatgpt.com"
    // Keep login/challenge handoffs in Gecko; route normal content links out.
    private static let embeddedChatGPTFlowHosts: Set<String> = [
        "account.live.com",
        "accounts.google.com",
        "accounts.openai.com",
        "appleid.apple.com",
        "auth.openai.com",
        "auth0.openai.com",
        "challenges.cloudflare.com",
        "idmsa.apple.com",
        "login.live.com",
        "login.microsoftonline.com",
        "login.openai.com",
        "openid.apple.com",
    ]
    private(set) var tabs: [Tab] = []
    private(set) var selectedTabIndex = -1

    var selectedTab: Tab? {
        tabs[safe: selectedTabIndex]
    }

    private weak var delegate: TabManagerDelegate?

    private lazy var isURLLenient: NSRegularExpression = {
        let pattern = "^\\s*(\\w+-+)*[\\w\\[]+(://[/]*|:|\\.)(\\w+-+)*[\\w\\[:]+([\\S&&[^\\w-]]\\S*)?\\s*$"
        return try! NSRegularExpression(pattern: pattern)
    }()

    init(delegate: TabManagerDelegate?) {
        self.delegate = delegate
    }

    private func closeSession(_ session: GeckoSession) {
        if session.isOpen() {
            session.setActive(false)
        }
        session.close()
    }

    private func persistState() {}

    private var reloadFlags: Int {
        GeckoSessionLoadFlags.none
    }

    private func loadURL(_ url: String, in tab: Tab, flags: Int = GeckoSessionLoadFlags.none) {
        tab.session.updateSettings(UserAgentController.shared.sessionSettings(for: url, tabID: tab.id))
        tab.session.load(url, flags: flags)
    }

    private func makeTab(windowId: String?) -> Tab {
        Tab(session: createSession(windowId: windowId))
    }

    private func restoredURL(from value: String?) -> String? {
        guard let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedValue.isEmpty,
              trimmedValue.lowercased() != "about:blank" else {
            return nil
        }

        return trimmedValue
    }

    private func remoteURL(from value: String?) -> URL? {
        guard let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: trimmedValue),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = url.host,
              !host.isEmpty else {
            return nil
        }

        return url
    }

    private func shouldOpenLoadRequestExternally(session: GeckoSession, request: LoadRequest) -> Bool {
        guard (request.hasUserGesture || request.isRedirect),
              let index = tabIndex(for: session),
              shouldOpenExternallyFromChatGPT(
                targetURLString: request.uri,
                sourceURLString: request.triggerUri ?? tabs[index].url
              ) else {
            return false
        }

        return requestExternalOpen(request.uri)
    }

    private func shouldOpenExternallyFromChatGPT(targetURLString: String, sourceURLString: String?) -> Bool {
        guard let targetURL = remoteURL(from: targetURLString),
              isChatGPTURL(sourceURLString),
              !shouldKeepEmbeddedForChatGPT(targetURL) else {
            return false
        }

        return true
    }

    private func isChatGPTURL(_ value: String?) -> Bool {
        guard let url = remoteURL(from: value),
              let host = url.host?.lowercased() else {
            return false
        }

        return host == "chatgpt.com" ||
            host.hasSuffix(".chatgpt.com") ||
            host == "chat.openai.com"
    }

    private func shouldKeepEmbeddedForChatGPT(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }

        return isChatGPTURL(url.absoluteString) ||
            Self.embeddedChatGPTFlowHosts.contains { hostMatches(host, domain: $0) }
    }

    private func hostMatches(_ host: String, domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }

    @discardableResult
    private func requestExternalOpen(_ value: String) -> Bool {
        guard let url = remoteURL(from: value) else {
            return false
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.delegate?.tabManager(self, didRequestExternalOpen: url)
        }
        return true
    }

    private func scheduleFaviconUpdate(forTabAt index: Int) {
        guard tabs.indices.contains(index) else { return }
        tabs[index].favicon = nil
        delegate?.tabManager(self, didUpdateTabAt: index, reason: .favicon)
    }

    private func loadRestoredURLIfNeeded(for index: Int) {
        guard tabs.indices.contains(index) else {
            return
        }

        let tab = tabs[index]
        guard let url = tab.pendingRestoreURL else {
            return
        }

        tab.pendingRestoreURL = nil
        tab.suppressInitialNavigation = false
        loadURL(url, in: tab)
    }

    func createInitialTab() {
        let index = addTab(selecting: true, windowId: nil, at: nil)
        if let tab = tabs[safe: index] {
            load(Self.shellHomeURL, in: tab)
        }
    }

    @discardableResult
    func addTab(selecting: Bool, windowId: String? = nil, at insertionIndex: Int? = nil) -> Int {
        let tab = makeTab(windowId: windowId)
        let index = min(max(insertionIndex ?? tabs.count, 0), tabs.count)

        if index == tabs.count {
            tabs.append(tab)
        } else {
            tabs.insert(tab, at: index)
            if selectedTabIndex >= index {
                selectedTabIndex += 1
            }
        }

        delegate?.tabManagerDidChangeTabs(self)

        if selecting {
            selectTab(at: index)
        } else {
            persistState()
        }

        return index
    }

    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else {
            return
        }

        let previousIndex = tabs.indices.contains(selectedTabIndex) ? selectedTabIndex : nil

        selectedTabIndex = index
        tabs[index].session.setActive(true)

        delegate?.tabManager(self, didSelectTabAt: index, previousIndex: previousIndex)
        loadRestoredURLIfNeeded(for: index)
        persistState()
    }

    func removeTab(at index: Int) {
        guard tabs.indices.contains(index) else {
            return
        }

        let wasSelected = index == selectedTabIndex
        let removedTab = tabs.remove(at: index)
        UserAgentController.shared.clearOverrides(forTabID: removedTab.id)

        if tabs.isEmpty {
            selectedTabIndex = -1
            delegate?.tabManagerDidChangeTabs(self)
            let replacementIndex = addTab(selecting: true, windowId: nil, at: nil)
            if let replacementTab = tabs[safe: replacementIndex] {
                load(Self.shellHomeURL, in: replacementTab)
            }
            closeSession(removedTab.session)
            return
        }

        if wasSelected {
            selectedTabIndex = -1
        } else if index < selectedTabIndex {
            selectedTabIndex -= 1
        }

        delegate?.tabManagerDidChangeTabs(self)

        if wasSelected {
            let fallback = min(index, tabs.count - 1)
            selectTab(at: fallback)
        } else {
            persistState()
        }

        closeSession(removedTab.session)
    }

    func removeAllTabs() {
        guard !tabs.isEmpty else {
            return
        }

        let removedTabs = tabs
        tabs.removeAll(keepingCapacity: true)
        removedTabs.forEach { UserAgentController.shared.clearOverrides(forTabID: $0.id) }
        selectedTabIndex = -1
        delegate?.tabManagerDidChangeTabs(self)
        let replacementIndex = addTab(selecting: true, windowId: nil)
        if let replacementTab = tabs[safe: replacementIndex] {
            load(Self.shellHomeURL, in: replacementTab)
        }

        removedTabs.forEach { closeSession($0.session) }
    }

    func browse(to term: String) {
        guard let tab = selectedTab else {
            return
        }
        browse(to: term, in: tab)
    }

    func browse(to term: String, in tab: Tab) {
        let trimmedValue = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return
        }

        tab.suppressInitialNavigation = false
        tab.pendingDisplayText = trimmedValue

        let fullRange = NSRange(location: 0, length: (trimmedValue as NSString).length)
        let isURL = isURLLenient.firstMatch(in: trimmedValue, range: fullRange) != nil

        if isURL {
            load(trimmedValue, in: tab, flags: GeckoSessionLoadFlags.none)
            return
        }

        let searchTarget = searchURL(for: trimmedValue)
        loadURL(searchTarget, in: tab)
    }

    func load(_ url: String, in tab: Tab, flags: Int = GeckoSessionLoadFlags.none) {
        let trimmedValue = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return
        }

        tab.suppressInitialNavigation = false
        tab.pendingDisplayText = trimmedValue
        loadURL(trimmedValue, in: tab, flags: flags)
    }

    func reload(_ tab: Tab) {
        guard let target = restoredURL(from: tab.url) else {
            load(Self.shellHomeURL, in: tab, flags: reloadFlags)
            return
        }

        tab.session.updateSettings(UserAgentController.shared.sessionSettings(for: target, tabID: tab.id))
        tab.session.reload(flags: reloadFlags)
    }

    func tabIndex(for session: GeckoSession) -> Int? {
        tabs.firstIndex(where: { $0.session === session })
    }

    func shareableURL(for tab: Tab) -> URL? {
        guard let value = tab.url?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value.lowercased() != "about:blank",
              let url = URL(string: value),
              let scheme = url.scheme,
              !scheme.isEmpty else {
            return nil
        }
        return url
    }

    func updateThumbnail(_ _: UIImage?, forTabAt index: Int) {
        guard tabs.indices.contains(index) else { return }
        tabs[index].thumbnail = nil
    }

    private func createSession(windowId: String?) -> GeckoSession {
        let session = GeckoSession()
        session.contentDelegate = self
        session.progressDelegate = self
        session.navigationDelegate = self
        session.open(windowId: windowId)
        return session
    }
}

extension TabManagerImplementation: ContentDelegate {
    func onTitleChange(session: GeckoSession, title: String) {
        guard let index = tabIndex(for: session) else {
            return
        }

        tabs[index].title = title
        delegate?.tabManager(self, didUpdateTabAt: index, reason: .title)
        persistState()
    }

    func onPreviewImage(session: GeckoSession, previewImageUrl: String) {}

    func onFocusRequest(session: GeckoSession) {
        guard selectedTab?.session === session else {
            return
        }

        session.setActive(true)
        session.setFocused(true)
    }

    func onCloseRequest(session: GeckoSession) {
        guard let index = tabIndex(for: session) else {
            return
        }
        removeTab(at: index)
    }

    func onFullScreen(session: GeckoSession, fullScreen: Bool) {}

    func onMetaViewportFitChange(session: GeckoSession, viewportFit: String) {}

    func onProductUrl(session: GeckoSession) {}

    func onCrash(session: GeckoSession) {
        guard let index = tabIndex(for: session) else {
            return
        }
        removeTab(at: index)
    }

    func onKill(session: GeckoSession) {
        guard let index = tabIndex(for: session) else {
            return
        }
        removeTab(at: index)
    }

    func onFirstComposite(session: GeckoSession) {}

    func onFirstContentfulPaint(session: GeckoSession) {}

    func onPaintStatusReset(session: GeckoSession) {}

    func onWebAppManifest(session: GeckoSession, manifest: Any) {}

    func onSlowScript(session: GeckoSession, scriptFileName: String) async -> SlowScriptResponse {
        guard let index = tabIndex(for: session) else {
            return .halt
        }

        let tab = tabs[index]
        if isChatGPTURL(tab.url) ||
            isChatGPTURL(tab.pendingDisplayText) ||
            isChatGPTURL(tab.pendingRestoreURL) {
            return .resume
        }

        return .halt
    }

    func onShowDynamicToolbar(session: GeckoSession) {}

    func onCookieBannerDetected(session: GeckoSession) {}

    func onCookieBannerHandled(session: GeckoSession) {}

    func onExternalResponse(session: GeckoSession, response: ExternalResponseInfo) {
    }

    func onSavePdf(session: GeckoSession, request: SavePdfInfo) {
    }
}

extension TabManagerImplementation: NavigationDelegate {
    func onLocationChange(session: GeckoSession, url: String?, permissions: [ContentPermission]) {
        guard let index = tabIndex(for: session) else {
            return
        }

        let normalizedURL = url?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if tabs[index].suppressInitialNavigation,
           let normalizedURL,
           normalizedURL.hasPrefix("about:blank") {
            return
        }

        if let normalizedURL, !normalizedURL.isEmpty {
            tabs[index].suppressInitialNavigation = false
        }

        if let url {
            session.updateSettings(UserAgentController.shared.sessionSettings(for: url, tabID: tabs[index].id))
        }

        tabs[index].url = url
        tabs[index].pendingDisplayText = nil
        tabs[index].favicon = nil
        delegate?.tabManager(self, didUpdateTabAt: index, reason: .location)
        scheduleFaviconUpdate(forTabAt: index)
        persistState()
    }

    func onCanGoBack(session: GeckoSession, canGoBack: Bool) {
        guard let index = tabIndex(for: session) else {
            return
        }

        tabs[index].canGoBack = canGoBack
        delegate?.tabManager(self, didUpdateTabAt: index, reason: .navigationState)
    }

    func onCanGoForward(session: GeckoSession, canGoForward: Bool) {
        guard let index = tabIndex(for: session) else {
            return
        }

        tabs[index].canGoForward = canGoForward
        delegate?.tabManager(self, didUpdateTabAt: index, reason: .navigationState)
    }

    func onLoadRequest(session: GeckoSession, request: LoadRequest) async -> AllowOrDeny {
        if shouldOpenLoadRequestExternally(session: session, request: request) {
            return .deny
        }

        return .allow
    }

    func onSubframeLoadRequest(session: GeckoSession, request: LoadRequest) async -> AllowOrDeny {
        .allow
    }

    func onNewSession(session: GeckoSession, uri: String, windowId: String) async -> GeckoSession? {
        if let index = tabIndex(for: session),
           shouldOpenExternallyFromChatGPT(targetURLString: uri, sourceURLString: tabs[index].url),
           requestExternalOpen(uri) {
            return nil
        }

        let newSession = GeckoSession()
        newSession.contentDelegate = self
        newSession.progressDelegate = self
        newSession.navigationDelegate = self

        let newTab = Tab(session: newSession)
        newSession.updateSettings(UserAgentController.shared.sessionSettings(for: uri, tabID: newTab.id))
        newTab.url = uri
        newTab.favicon = nil

        let insertionIndex = tabIndex(for: session).map { $0 + 1 }
        let index = min(max(insertionIndex ?? tabs.count, 0), tabs.count)
        if index == tabs.count {
            tabs.append(newTab)
        } else {
            tabs.insert(newTab, at: index)
            if selectedTabIndex >= index {
                selectedTabIndex += 1
            }
        }

        delegate?.tabManagerDidChangeTabs(self)
        delegate?.tabManager(self, didUpdateTabAt: index, reason: .location)
        scheduleFaviconUpdate(forTabAt: index)
        persistState()
        delegate?.tabManager(self, animateNewTabSelectionAt: index) { [weak self] in
            self?.selectTab(at: index)
        }
        return newSession
    }
}

extension TabManagerImplementation: ProgressDelegate {
    func onPageStart(session: GeckoSession, url: String) {
        guard let index = tabIndex(for: session) else {
            return
        }

        let currentHost = tabs[index].url.flatMap { UserAgentController.shared.extractHost(from: $0) }
        let requestedHost = UserAgentController.shared.extractHost(from: url)
        let desiredSettings = UserAgentController.shared.sessionSettings(for: url, tabID: tabs[index].id)

        if currentHost != nil,
           requestedHost != nil,
           currentHost != requestedHost,
           (desiredSettings.userAgentOverride != session.userAgentOverride ||
            desiredSettings.userAgentMode != session.userAgentMode ||
            desiredSettings.viewportMode != session.viewportMode) {
            loadURL(url, in: tabs[index])
        }

        tabs[index].isLoading = true
        tabs[index].progress = 0
        delegate?.tabManager(self, didUpdateTabAt: index, reason: .loading)
    }

    func onPageStop(session: GeckoSession, success: Bool) {
        guard let index = tabIndex(for: session) else {
            return
        }

        tabs[index].isLoading = false
        delegate?.tabManager(self, didUpdateTabAt: index, reason: .loading)
        delegate?.tabManager(self, didUpdateTabAt: index, reason: .thumbnail)
    }

    func onProgressChange(session: GeckoSession, progress: Int) {
        guard let index = tabIndex(for: session) else {
            return
        }

        tabs[index].progress = Float(progress) / 100
        delegate?.tabManager(self, didUpdateTabAt: index, reason: .loading)
    }
}
